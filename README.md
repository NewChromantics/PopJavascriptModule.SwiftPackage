PopJavascriptModule.SwiftPackage
===========================

An extension to Swift's JavaScriptCore implementation which adds;
- Module & `import`/`export` support
- `setTimeout()` implementation
- `console.log()` implementation
- Simple `Call()` and `await CallAsync()` swift->js interface (both of which `throw` when js throws an exception)

There is a huge amount that could be added to this, but I haven't 
needed to make any changes to the basic implementation for 18 months. 


Known Issues
----------------
These are low hanging fruit, but haven't stopped me using the package.

- The `import`/`export` conversion is very slow
- `Call`/`CallAsync` returns are all strings.

There are probably many more, feel free to add issues & PRs.
