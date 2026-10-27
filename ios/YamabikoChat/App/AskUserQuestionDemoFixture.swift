#if DEBUG
import Foundation

enum AskUserQuestionDemoFixture {
    static var questions: [AskUserQuestionItem] {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-QuestionChoicesFixture") {
            return [
                AskUserQuestionItem(id: "person", question: "あなたが一番尊敬するのは誰ですか？"),
                AskUserQuestionItem(
                    header: "尊敬する理由",
                    id: "reasons",
                    multiSelect: true,
                    options: [
                        AskUserQuestionOption(label: "考え方 (Recommended)", description: "その人の思想や価値観に共感している。"),
                        AskUserQuestionOption(label: "行動力", description: "難しい状況でも行動を起こした。"),
                        AskUserQuestionOption(label: "功績", description: "社会に大きな影響を与えた。")
                    ],
                    question: "どの点を尊敬していますか？複数選択できます。"
                )
            ]
        }
        if arguments.contains("-QuestionLongFixture") {
            return [AskUserQuestionItem(
                id: "long",
                options: (1...12).map {
                    AskUserQuestionOption(label: "選択肢\($0)", description: "考え方や行動について詳しく教えてください。")
                },
                question: String(repeating: "あなたが尊敬する人について、その人の考え方や行動、影響を受けた出来事を教えてください。", count: 8)
            )]
        }
        return [AskUserQuestionItem(
            id: "person",
            question: arguments.contains("-QuestionFragmentFixture") ? "質" : "あなたが一番尊敬するのは誰ですか？"
        )]
    }
}
#endif
