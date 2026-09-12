/// Selects the 64-bit integer helpers supported by the target platform.
///
/// Only the JavaScript target lacks 64-bit integers: it stores every `int` as a
/// double and its `ByteData` 64-bit accessors throw. Native platforms and
/// WebAssembly both have real 64-bit integers, so both use the native helpers.
///
/// The conditions test for a native platform rather than for JavaScript, because
/// the first matching one wins and an unrecognized target should degrade to the
/// narrower-but-correct fallback instead of crashing on a missing accessor:
///
/// | target      | `dart.library.io` | `dart.library.isolate` | selected |
/// | ----------- | ----------------- | ---------------------- | -------- |
/// | native      | yes               | yes                    | native   |
/// | `dart2wasm` | no                | yes                    | native   |
/// | `dart2js`   | no                | no                     | JS       |
library;

export 'package:pscore/src/int64_js.dart' if (dart.library.io) 'package:pscore/src/int64_native.dart' if (dart.library.isolate) 'package:pscore/src/int64_native.dart';
