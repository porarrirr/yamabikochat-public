import Foundation
import XCTest
@testable import YamabikoChat

final class AgentSkillRepositoryTests: XCTestCase {
    private var temporaryRoot: URL!
    private var repository: AgentSkillRepository!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-skill-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        repository = AgentSkillRepository(rootURL: temporaryRoot.appendingPathComponent("installed"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    func testManifestInventoryInstallAndExplicitOrder() throws {
        let source = try makeSkill(
            name: "review-helper",
            descriptionYAML: ">\n  Review changes carefully\n  and report risks.",
            extraFiles: [
                "references/checklist.md": "Check every edge case.",
                "scripts/audit.py": "#!/usr/bin/env python3\nprint('never run locally')",
            ],
            extraFrontMatter: """
            license: MIT
            compatibility: Requires git
            allowed-tools:
              - shell
              - read
            metadata:
              author: Example
            """
        )

        let preview = try repository.inspect(sourceURL: source)
        XCTAssertEqual(preview.manifest.name, "review-helper")
        XCTAssertTrue(preview.manifest.description.contains("Review changes carefully"))
        XCTAssertEqual(preview.manifest.allowedTools, ["shell", "read"])
        XCTAssertEqual(preview.manifest.metadata["author"], "Example")
        XCTAssertTrue(preview.hasScripts)
        XCTAssertEqual(preview.files.map(\.path), ["SKILL.md", "references/checklist.md", "scripts/audit.py"])
        XCTAssertThrowsError(try repository.install(preview, trusted: false, allowReplacement: false))

        _ = try repository.install(preview, trusted: true, allowReplacement: false)
        let context = try XCTUnwrap(repository.requestContext(
            for: "@review-helper then @review-helper and @unknown",
            conversationID: "42",
            providerSupportsTools: true
        ))
        XCTAssertEqual(context.explicitlyRequestedNames, ["review-helper"])
        XCTAssertEqual(context.skillFilePaths.count, 1)
        XCTAssertEqual(context.explicitMessageIndices, [0])
        XCTAssertTrue(context.skillFilePaths[0].hasSuffix("review-helper/SKILL.md"))
        XCTAssertEqual(context.catalog.map(\.name), ["review-helper"])
    }

    func testImportsStandaloneMarkdownAsSkillFile() throws {
        let markdownURL = temporaryRoot.appendingPathComponent("standalone.md")
        try Data("""
        ---
        name: standalone-skill
        description: Imported from one Markdown file
        ---
        Follow the standalone instructions.
        """.utf8).write(to: markdownURL)

        let preview = try repository.inspect(sourceURL: markdownURL)

        XCTAssertEqual(preview.manifest.name, "standalone-skill")
        XCTAssertEqual(preview.files.map(\.path), ["SKILL.md"])
        _ = try repository.install(preview, trusted: true, allowReplacement: false)
        XCTAssertTrue(try String(contentsOf: repository.rootForEnabledSkill(name: "standalone-skill").appendingPathComponent("SKILL.md"), encoding: .utf8).contains("Follow the standalone instructions."))
    }

    func testEnabledStatePersistsAndReplacementPreservesIt() throws {
        let first = try repository.inspect(sourceURL: makeSkill(name: "stable-skill"))
        _ = try repository.install(first, trusted: true, allowReplacement: false)
        try repository.setEnabled(false, name: "stable-skill")

        let replacementSource = try makeSkill(
            name: "stable-skill",
            extraFiles: ["references/new.md": "replacement"]
        )
        let replacement = try repository.inspect(sourceURL: replacementSource)
        XCTAssertTrue(replacement.replacesExisting)
        _ = try repository.install(replacement, trusted: true, allowReplacement: true)
        XCTAssertFalse(try XCTUnwrap(repository.installedSkills.first).isEnabled)

        let reloaded = AgentSkillRepository(rootURL: temporaryRoot.appendingPathComponent("installed"))
        XCTAssertFalse(try XCTUnwrap(reloaded.installedSkills.first).isEnabled)
        try reloaded.delete(name: "stable-skill")
        XCTAssertTrue(reloaded.installedSkills.isEmpty)
    }

    func testRejectsMultipleSkillFilesAndSymlinks() throws {
        let multiple = try makeSkill(name: "multiple")
        let nested = multiple.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("---\nname: nested\ndescription: nested\n---\n".utf8)
            .write(to: nested.appendingPathComponent("SKILL.md"))
        XCTAssertThrowsError(try repository.inspect(sourceURL: multiple))

        let linked = try makeSkill(name: "linked")
        try FileManager.default.createSymbolicLink(
            at: linked.appendingPathComponent("escape.txt"),
            withDestinationURL: temporaryRoot.appendingPathComponent("outside.txt")
        )
        XCTAssertThrowsError(try repository.inspect(sourceURL: linked))
    }

    func testRejectsInvalidNameAndOversizedSkillFile() throws {
        let invalid = try makeSkill(name: "Invalid_Name")
        XCTAssertThrowsError(try repository.inspect(sourceURL: invalid))

        let oversized = try makeSkill(name: "too-large")
        let header = "---\nname: too-large\ndescription: oversized\n---\n"
        let body = String(repeating: "x", count: Int(AgentSkillLimits.skillFileBytes))
        try Data((header + body).utf8).write(to: oversized.appendingPathComponent("SKILL.md"))
        XCTAssertThrowsError(try repository.inspect(sourceURL: oversized))
    }

    func testNativeRequestsDoNotExposeReplacedSkillTools() async throws {
        let preview = try repository.inspect(sourceURL: makeSkill(name: "scoped-skill"))
        _ = try repository.install(preview, trusted: true, allowReplacement: false)
        let resolver = ProviderRequestSettingsResolver(
            modelService: OpenRouterModelService(credentialStore: KeychainStore()),
            skillRepository: repository
        )

        let standard = try await resolver.resolve(
            settings: AppSettings(),
            provider: "OPENAI",
            model: "gpt-5.6",
            toolScope: .all
        )
        let internalRequest = try await resolver.resolve(
            settings: AppSettings(),
            provider: "OPENAI",
            model: "gpt-5.6",
            toolScope: .providerOnly
        )

        XCTAssertFalse(standard.tools.contains { $0.payload["name"] == "activate_skill" })
        XCTAssertFalse(standard.tools.contains { $0.payload["name"] == "read_skill_resource" })
        XCTAssertFalse(internalRequest.tools.contains { $0.payload["name"] == "activate_skill" })
    }

    func testPromptComposerKeepsPreviouslySentUserMessagesByteStableAcrossTurns() throws {
        let preview = try repository.inspect(sourceURL: makeSkill(name: "stable-skill"))
        _ = try repository.install(preview, trusted: true, allowReplacement: false)
        let firstSource = [
            ProviderRequestMessage(role: "user", content: "@stable-skill review this")
        ]
        let first = try AgentSkillPromptComposer.apply(
            repository: repository,
            to: firstSource,
            conversationID: "conversation-1",
            providerSupportsTools: true
        )
        let secondSource = [
            ProviderRequestMessage(role: "user", content: "@stable-skill review this"),
            ProviderRequestMessage(role: "assistant", content: "first answer"),
            ProviderRequestMessage(role: "user", content: "continue")
        ]
        let second = try AgentSkillPromptComposer.apply(
            repository: repository,
            to: secondSource,
            conversationID: "conversation-1",
            providerSupportsTools: true
        )

        XCTAssertEqual(first.messages[0].content, second.messages[0].content)
        XCTAssertEqual(first.messages[0].content, firstSource[0].content)
        XCTAssertTrue(first.messages[0].content.contains("@stable-skill review this"))
        XCTAssertFalse(first.messages[0].content.contains("<explicit_agent_skill"))
        XCTAssertFalse(second.messages[2].content.contains("<available_agent_skills>"))
        XCTAssertEqual(second.currentContext?.explicitMessageIndices, [0])
    }

    func testAtMentionAutocompleteAndLegacyDollarInvocation() throws {
        XCTAssertEqual(AgentSkillInvocationSyntax.autocompletePrefix(in: "@"), "")
        XCTAssertEqual(AgentSkillInvocationSyntax.autocompletePrefix(in: "Please @rev"), "rev")
        XCTAssertNil(AgentSkillInvocationSyntax.autocompletePrefix(in: "mail@example.com"))
        XCTAssertEqual(
            AgentSkillInvocationSyntax.completingAutocomplete(in: "Please @rev", with: "review-helper"),
            "Please @review-helper "
        )
        XCTAssertEqual(
            AgentSkillRepository.explicitSkillNames(
                in: "@review-helper and $legacy-skill, /skill:manual, not mail@review-helper.com",
                allowed: ["review-helper", "legacy-skill", "manual"]
            ),
            ["review-helper", "legacy-skill", "manual"]
        )
    }

    func testSkillScriptsRunInPythonAndDisappearWhenDisabled() async throws {
        let source = try makeSkill(name: "script-skill", extraFiles: [
            "references/rules.txt": "checked",
            "scripts/check.py": """
            import argparse
            from pathlib import Path
            parser = argparse.ArgumentParser()
            parser.add_argument('input')
            args = parser.parse_args()
            rules = Path(__file__).parent.parent / 'references/rules.txt'
            Path('result.txt').write_text(rules.read_text() + ':' + Path(args.input).read_text())
            print('script-completed')
            """,
        ])
        let preview = try repository.inspect(sourceURL: source)
        _ = try repository.install(preview, trusted: true, allowReplacement: false)
        let context = try XCTUnwrap(repository.requestContext(
            for: "@script-skill check", conversationID: "skill-runtime", providerSupportsTools: true
        ))
        XCTAssertEqual(context.skillFilePaths, [try repository.rootForEnabledSkill(name: "script-skill").appendingPathComponent("SKILL.md").path])
        XCTAssertEqual(context.catalog.first?.filePath, context.skillFilePaths.first)
        XCTAssertFalse(try repository.pythonFiles().contains { $0.path.hasSuffix("state.json") })

        let sessions = PythonSessionStore(rootOverride: temporaryRoot.appendingPathComponent("sessions"))
        let worker = PythonWorker(sessions: sessions, timeoutSeconds: 30)
        let python = PythonExecuteTool(
            worker: worker, sessions: sessions,
            attachments: AttachmentRepository(generatedFilesRootOverride: temporaryRoot.appendingPathComponent("artifacts")),
            skillRepository: repository
        )
        let code = """
        import runpy, sys
        from pathlib import Path
        Path('input.txt').write_text('日本語')
        old_argv = sys.argv[:]
        try:
            sys.argv = ['/skills/script-skill/scripts/check.py', 'input.txt']
            runpy.run_path(sys.argv[0], run_name='__main__')
        finally:
            sys.argv = old_argv
        assert Path('result.txt').read_text() == 'checked:日本語'
        try:
            Path('/skills/script-skill/references/rules.txt').write_text('modified')
            raise AssertionError('skill write allowed')
        except PermissionError:
            pass
        """
        let arguments = String(decoding: try JSONEncoder().encode(["code": code]), as: UTF8.self)
        let result = try await python.execute(call: ToolCall(
            id: "check", name: PythonExecuteTool.name, argumentsJSON: arguments,
            providerMetadata: ["pythonSessionId": "skill-runtime"]
        ))
        let response = try JSONDecoder().decode(PythonExecutionResponse.self, from: Data(result.content.utf8))
        XCTAssertEqual(response.status, "ok", response.error?.traceback ?? response.stderr)
        XCTAssertTrue(response.stdout.contains("script-completed"))
        XCTAssertFalse(result.artifacts.contains { $0.path.contains("/skills/") })
        try repository.setEnabled(false, name: "script-skill")
        XCTAssertTrue(try repository.pythonFiles().isEmpty)
        let revoked = try await worker.execute(sessionID: "skill-runtime", code: """
        assert not Path('/skills/script-skill/SKILL.md').exists()
        assert Path('result.txt').read_text() == 'checked:日本語'
        """, reset: false, attachmentPaths: [], skillFiles: try repository.pythonFiles())
        XCTAssertEqual(revoked.status, "ok", revoked.error?.traceback ?? revoked.stderr)
        await worker.resetSession(sessionID: "skill-runtime")
    }

    func testBundledInstallationPublishesOneCompleteCatalog() throws {
        let bundle = temporaryRoot.appendingPathComponent("bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        for name in ["first-skill", "second-skill", "third-skill"] {
            try FileManager.default.moveItem(at: makeSkill(name: name), to: bundle.appendingPathComponent(name))
        }
        var catalogs: [[String]] = []
        let subscription = repository.skillsPublisher.dropFirst().sink { catalogs.append($0.map(\.id)) }
        defer { subscription.cancel() }

        try repository.installBundledSkills(from: bundle)

        XCTAssertEqual(catalogs, [["first-skill", "second-skill", "third-skill"]])
        try repository.installBundledSkills(from: bundle)
        XCTAssertEqual(catalogs.count, 1)
    }

    func testReloadStillRejectsModifiedResourceContents() throws {
        let preview = try repository.inspect(sourceURL: makeSkill(name: "verified-skill",
            extraFiles: ["references/source.md": "https://example.com/original"]))
        XCTAssertEqual(preview.externalURLs, ["https://example.com/original"])
        _ = try repository.install(preview, trusted: true, allowReplacement: false)
        let root = try repository.rootForEnabledSkill(name: "verified-skill")
        try Data("https://example.com/modified".utf8).write(to: root.appendingPathComponent("references/source.md"))

        let reloaded = AgentSkillRepository(rootURL: temporaryRoot.appendingPathComponent("installed"))

        XCTAssertTrue(reloaded.installedSkills.isEmpty)
    }

    func testBundledSkillsSeedOnceAndPreserveUserChoices() throws {
        let bundle = try XCTUnwrap(Bundle.main.url(forResource: "BundledAgentSkills", withExtension: nil))
        try repository.installBundledSkills(from: bundle)
        let creator = try XCTUnwrap(repository.enabledSkills.first { $0.manifest.name == "skill-creator" })
        XCTAssertFalse(creator.manifest.description.isEmpty)
        XCTAssertTrue(try String(contentsOf: bundle.appendingPathComponent("skill-creator/SKILL.md"), encoding: .utf8).contains("zipfile"))
        try repository.setEnabled(false, name: creator.id)
        try repository.installBundledSkills(from: bundle)
        XCTAssertFalse(try XCTUnwrap(repository.installedSkills.first { $0.id == creator.id }).isEnabled)
        try repository.delete(name: creator.id)
        let reloaded = AgentSkillRepository(rootURL: temporaryRoot.appendingPathComponent("installed"))
        try reloaded.installBundledSkills(from: bundle)
        XCTAssertFalse(reloaded.installedSkills.contains { $0.id == creator.id })
    }

    func testBundledSkillDoesNotReplaceExistingUserSkill() throws {
        let preview = try repository.inspect(sourceURL: makeSkill(name: "skill-creator", descriptionYAML: "User version"))
        _ = try repository.install(preview, trusted: true, allowReplacement: false)
        let bundle = try XCTUnwrap(Bundle.main.url(forResource: "BundledAgentSkills", withExtension: nil))
        try repository.installBundledSkills(from: bundle)
        XCTAssertEqual(repository.installedSkills.first?.manifest.description, "User version")
    }

    func testSeededBundledSkillSkipsResourcesAndStillInstallsNewSkills() throws {
        let bundle = temporaryRoot.appendingPathComponent("bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let seeded = bundle.appendingPathComponent("different-folder-name", isDirectory: true)
        try FileManager.default.moveItem(at: makeSkill(name: "seeded-skill"), to: seeded)
        try repository.installBundledSkills(from: bundle)
        try repository.delete(name: "seeded-skill")
        // Already-seeded resources must not be staged or inventoried on later launches.
        try FileManager.default.createSymbolicLink(
            at: seeded.appendingPathComponent("unused-resource"),
            withDestinationURL: temporaryRoot.appendingPathComponent("missing")
        )
        try FileManager.default.moveItem(
            at: makeSkill(name: "new-bundled-skill"),
            to: bundle.appendingPathComponent("new", isDirectory: true)
        )

        let reloaded = AgentSkillRepository(rootURL: temporaryRoot.appendingPathComponent("installed"))
        try reloaded.installBundledSkills(from: bundle)

        XCTAssertEqual(reloaded.installedSkills.map(\.id), ["new-bundled-skill"])
    }

    private func makeSkill(
        name: String,
        descriptionYAML: String = "A test skill",
        extraFiles: [String: String] = [:],
        extraFrontMatter: String = ""
    ) throws -> URL {
        let source = temporaryRoot.appendingPathComponent("source-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let markdown = "---\nname: \(name)\ndescription: \(descriptionYAML)\n"
            + extraFrontMatter
            + "\n---\nFollow these instructions for \(name).\n"
        try Data(markdown.utf8).write(to: source.appendingPathComponent("SKILL.md"))
        for (path, content) in extraFiles {
            let url = source.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(content.utf8).write(to: url)
        }
        return source
    }
}
