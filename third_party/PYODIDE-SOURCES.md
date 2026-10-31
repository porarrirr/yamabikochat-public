# Pyodide source availability and modifications

YamabikoChat distributes Pyodide 314.0.7, including CPython 3.14.2, under their
respective licenses. Pyodide's covered source remains available under MPL-2.0;
the app's MIT license does not replace it. See PYODIDE_LICENSE.txt in the app,
or [the preserved license](https://github.com/porarrirr/yamabikochat-public/blob/main/third_party/pyodide-LICENSE.txt).

## Exact upstream source

- Revision: `b1e4fcc2488962f6360a97f19b9982d6fdb5d16f` (Pyodide 314.0.7)
- Source tree: https://github.com/pyodide/pyodide/tree/b1e4fcc2488962f6360a97f19b9982d6fdb5d16f
- Source archive: https://codeload.github.com/pyodide/pyodide/tar.gz/b1e4fcc2488962f6360a97f19b9982d6fdb5d16f
- Archive SHA-256: `a9c7ac66311ed7e0805b9970054ee5be4f69d02204d28bffe4b017310a24bad9`
- CPython source: https://github.com/python/cpython/tree/v3.14.2
- Core dependency revisions and downloads: `Makefile.envs` and `cpython/Makefile` in that source tree.
- Build instructions: https://github.com/pyodide/pyodide/blob/b1e4fcc2488962f6360a97f19b9982d6fdb5d16f/docs/development/building-from-sources.md

For a full upstream build, use a Git checkout at that revision and initialize its
pinned submodules as described by the upstream instructions. The source archive
alone does not contain Git submodules. All sources above can be obtained without
purchasing the app.

## YamabikoChat modifications

The app lowers the WebAssembly memory maximum from 4 GiB to 512 MiB. The initial
memory size remains 480 pages. The original npm archive is SHA-512 verified;
`scripts/bootstrap-python-wasm.py` then changes the Wasm memory declaration before
recording the resulting bundle's SHA-256 hashes. It also limits the package lock
to bundled packages; it does not modify the Python package wheels.

The corresponding source change to Pyodide's linker setting is published under
MPL-2.0 in this patch:

https://github.com/porarrirr/yamabikochat-public/blob/main/third_party/pyodide/memory-limit.patch

Apply it at the pinned Pyodide source root with `patch -p1 < memory-limit.patch`
before following the upstream build instructions. It changes
`-s MAXIMUM_MEMORY=4GB` to `-s MAXIMUM_MEMORY=512MB`. A source rebuild is not claimed
to be byte-identical to the post-processed npm binary.

The actual binary transformation and archive-integrity check are also public:

https://github.com/porarrirr/yamabikochat-public/blob/main/ios/scripts/bootstrap-python-wasm.py

The application host and Python broker are separate original MIT-licensed code.
The Pyodide source patch retains MPL-2.0. Copyright notices and license texts for
CPython, core native dependencies, and the scientific package wheels are retained
in the accompanying Python license documents.
