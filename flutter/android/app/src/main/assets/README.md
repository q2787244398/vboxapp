# Android embedded Node.js runtime

`NodeBridge` expects a **real executable** at the asset path `node` and copies
it to the app's private files directory before launch. This repository does
not include a native executable placeholder: an empty or text file would make
release builds appear valid but fail at runtime.

Provide an ABI-matched nodejs-mobile executable during packaging, for example:

```text
android/app/src/main/assets/node
```

The executable must support the target Android ABIs and run the bundle passed
as its first argument. Keep this binary out of source control if licensing or
size constraints require it; the CI packaging step should fail when it is
absent.
