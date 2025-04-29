import JavaScriptCore
import Combine



struct JavascriptError : LocalizedError
{
	let description: String
	
	init(_ description: String) {
		self.description = description
	}
	
	var errorDescription: String? {
		description
	}
}


//	set timeout via objc JSExport
//	https://gist.github.com/heilerich/e23cfc6fe434919de972140147f83f6f
@objc protocol JSTimerExport : JSExport 
{
	func setTimeout(_ callback : JSValue,_ ms : Double) -> String
	func clearTimeout(_ identifier: String)
	func setInterval(_ callback : JSValue,_ ms : Double) -> String
}

@objc class JSTimer: NSObject, JSTimerExport 
{
	static let shared = JSTimer()
	
	var timers = [String: Timer]()
	
	let queue = DispatchQueue(label: "jstimers")

	static func registerInto(jsContext: JSContext) 
	{
		jsContext.setObject(shared, forKeyedSubscript: "timerJS" as (NSCopying & NSObjectProtocol))
		jsContext.evaluateScript(
		"""
		function setTimeout(callback, ms) {
			return timerJS.setTimeout(callback, ms)
		}
		function clearTimeout(identifier) {
			timerJS.clearTimeout(identifier)
		}
		function setInterval(callback, ms) {
			return timerJS.setInterval(callback, ms)
		}
		function clearInterval(identifier) {
			timerJS.clearTimeout(identifier)
		}
		"""
		)
	}

	func clearTimeout(_ identifier: String) {
		queue.sync {
			let timer = timers.removeValue(forKey: identifier)
			timer?.invalidate()
		}
	}

	@MainActor
	func setInterval(_ callback: JSValue,_ ms: Double) -> String
	{
		return createTimer(callback: callback, ms: ms, repeats: true)
	}

	@MainActor
	func setTimeout(_ callback: JSValue, _ ms: Double) -> String
	{
		return createTimer(callback: callback, ms: ms , repeats: false)
	}

	@MainActor
	func createTimer(callback: JSValue, ms: Double, repeats : Bool) -> String {
		let timeInterval  = ms/1000.0
		let uuid = UUID().uuidString
		
		//	gr: the timer has to run on the main thread otherwise the callback doesn't come back
		//		because... it's in swift? or because the javascript thread has no queue? not sure
		//queue.sync
		DispatchQueue.main.async
		{
			let timer = Timer.scheduledTimer(timeInterval: timeInterval,
											 target: self,
											 selector: #selector(self.callJsCallback),
											 userInfo: callback,
											 repeats: repeats)
			self.timers[uuid] = timer
		}
		return uuid
	}

	@objc func callJsCallback(_ timer: Timer) {
		queue.sync {
			let callback = (timer.userInfo as! JSValue)
			callback.call(withArguments: nil)
		}
	}
}





//	JSContext with extra built-ins, import/export support extra and error handling
extension JSContext
{
	var context : JSContext
	{
		return self
	}
	
	var contextGroup : JSContextGroupRef
	{
		return JSContextGetGroup(context.jsGlobalContextRef)!
	}
	
	var filename : String
	{
		return name ?? ""
	}

	var lastError : String?
	{
		if ( context.exception == nil )
		{
			return nil
		}
		else
		{
			//	debugDescription always says Optional()
			//let errorMessage = context.exception.debugDescription ?? ""
			return context.exception.description
		}
	}

	
	//	make a functor (@@convention = obj-c block) to add to the context
	static let ImportModuleFunctor :/* @convention(block) */(String,JavascriptModule) -> (JSValue?) =
	{
		importFilename, moduleOwner in
		let context = JSContext.current()!
		let contextGroup = context.contextGroup
		
		do
		{
			let (importPath,url) = moduleOwner.ResolveFilePath( filename:importFilename, parentFilename: context.filename )

			//let expandedPath = NSString(string: importpath).expandingTildeInPath
			//print("Importing \(importPath) from \(context.filename)...")
			//guard let expandedPath = Bundle.main.url(forResource: importPath, withExtension: "") else
			guard let expandedPath = url else
			{
				throw JavascriptError("File \(importFilename) not resolved")
			}
			
			var fileContent = try String(contentsOf: expandedPath, encoding:String.Encoding.ascii)
			fileContent = fileContent.replacingOccurrences(of: "\r\n", with: "\n")
			
			//	non ascii chars in JSContext sources fail to load
			//	to easily detect them, we can convert Swift string to an NSString and look for differences
			let fileContentNs = fileContent as NSString
			if ( fileContent.count != fileContentNs.length )
			{
				throw JavascriptError("File \(expandedPath) has non ascii chars")
			}
			
			//	create a new context
			let NewGlobalContext = JSGlobalContextCreateInGroup(contextGroup, nil)
			let NewContext = JSContext(jsGlobalContextRef: NewGlobalContext!)!
			//NewContext.name = "\(context.name!) / \(importpath)"
			NewContext.name = importPath

			//let NewContext = JSContext()!
			let NewContextExports = try! NewContext.InitModuleSupport(moduleOwner: moduleOwner)
			
			_ = NewContext.evaluateES6Script(fileContent)
			if ( NewContext.exception != nil )
			{
				throw JavascriptError(NewContext.lastError!)
			}
			
			//print("Finished importing module \(importFilename).")
			
			return NewContextExports
		}
		catch
		{
			//	we cannot throw, set the exception
			let exceptionString = "\(JavascriptModule.ImportModuleFunctionSymbol)(\(importFilename)) failed; \(error.localizedDescription)"
			print(exceptionString)
			let exceptionValue = JSValue.init(newErrorFromMessage: exceptionString, in: context)
			context.exception = exceptionValue
			return nil
		}
	}
	
	
	//	make a functor (@@convention = obj-c block) to add to the context
	static let consolelogfunctor: @convention(block) (String) -> (JSValue?) =
	{
		message in
		let context = JSContext.current()!
		
		let name = context.name ?? "unnamed"
		print("\(name)::console.log-->\(message)")
		return nil
	}
	
	//	returns exports object, akin to the exported "module" in normal js
	func InitModuleSupport(moduleOwner:JavascriptModule) throws -> JSValue
	{
		let global = context.globalObject!
		
		let ExistingExports = global.hasProperty(JavascriptModule.ModuleExportsSymbol as NSString as String)
		if ( ExistingExports )
		{
			throw JavascriptError("Context already has global exports symbol \(JavascriptModule.ModuleExportsSymbol)")
		}
		
		let NewContextExports = JSValue(newObjectIn: context)!
		//global.defineProperty(JavascriptModule.ModuleExportsSymbol as NSString, descriptor: NewContextExports)
		global.setObject( NewContextExports, forKeyedSubscript: JavascriptModule.ModuleExportsSymbol as NSString)
		//global.setValue( NewContextExports, forProperty: JavascriptModule.ModuleExportsSymbol as NSString)
		let NowHasExports = global.hasProperty(JavascriptModule.ModuleExportsSymbol as NSString as String)
		if ( !NowHasExports )
		{
			throw JavascriptError("Context didn't register global exports symbol \(JavascriptModule.ModuleExportsSymbol)")
		}

		//	need to capture local variable
		let ImportModuleFunctorWrapper : @convention(block) (String) -> (JSValue?) =
		{
			path in
			return JSContext.ImportModuleFunctor(path,moduleOwner)
		}
		
		//	register global functors
		global.setObject( ImportModuleFunctorWrapper, forKeyedSubscript: JavascriptModule.ImportModuleFunctionSymbol as NSString)
		
		let console = JSValue(newObjectIn: context)
		console?.setValue( JSContext.consolelogfunctor, forProperty: "log" )
		global.setObject( console, forKeyedSubscript: "console" as NSString)

		//	add setTimeout
		JSTimer.registerInto(jsContext: context)
		
		
		let ExceptionHandler = { [self] (ctx: JSContext!, value: JSValue!) in
			
			let stacktrace = value.objectForKeyedSubscript("stack")?.toString() ?? ""
			let lineNumber = value.objectForKeyedSubscript("line")?.toInt32() ?? -1
			let column = value.objectForKeyedSubscript("column")?.toInt32() ?? -1
			let errorMeta = "Method=\(stacktrace); Line=\(lineNumber); column=\(column);"

			let ExceptionValue = value?.toString() ?? "???"
			
			let exceptionString = "Exception: \(ExceptionValue) \(errorMeta)"
			//print(exceptionString)
			let exceptionValue = JSValue.init(newErrorFromMessage: exceptionString, in: context)
			ctx.exception = exceptionValue!
		}
		
		//	gr: don't need this? just check exception after every call?
		//		if we use this exception handler, we need to set context's .exception
		context.exceptionHandler = ExceptionHandler
		
		return NewContextExports
	}

	func evaluateES6Script(_ originalScript:String) -> JSValue?
	{
		let ES5Script = RewriteES6ImportsAndExports(originalScript, importFunctionName: JavascriptModule.ImportModuleFunctionSymbol, exportSymbolName: JavascriptModule.ModuleExportsSymbol )
		return self.evaluateScript( ES5Script )
	}
	

}




public class JavascriptModule
{
	static public let ImportModuleFunctionSymbol = "__ImportModule"
	static public let ModuleExportsSymbol = "__exports"
	
	var context : JSContext!
	var contextGroup : JSContextGroupRef
	var resolveUrlForImport : (String)->URL?

	//	given ./hello.js in parent Folder/file.js
	//	we should resolve to Folder/hello.js
	func ResolveFilePath(filename:String, parentFilename:String) -> (String,URL?)
	{
		//	get path out of parent
		var parentPath = parentFilename.components(separatedBy: "/")
		//	pop filename from parent
		parentPath.removeLast()
		parentPath.append( filename )
		let filePath = parentPath.joined(separator: "/")
		
		let url = resolveUrlForImport(filename)
		
		return (filePath,url)
	}
	
	public init(_ script:String, moduleName:String,resolveUrlForImport:@escaping (String)->URL?) throws
	{
		self.resolveUrlForImport = resolveUrlForImport
		
		contextGroup = JSContextGroupCreate()
		let globalcontext = JSGlobalContextCreateInGroup(contextGroup, nil)
		context = JSContext(jsGlobalContextRef: globalcontext!)
		context.name = moduleName
				
		_ = try! context.InitModuleSupport( moduleOwner: self )

		//	load script - always returns undefined
		_ = context.evaluateES6Script(script)
		
		if ( context.exception != nil )
		{
			throw JavascriptError(context.lastError!)
		}
	}
	
	@MainActor	//	run all js on main thread
	public func Call(_ functionAndArgs:String) throws -> JSValue
	{
		//let Code = "\(functionName)()"
		let Code = functionAndArgs
		//	call a func
		let output = context.evaluateScript(Code)
		if ( context.exception != nil )
		{
			throw JavascriptError(context.lastError!)
		}
		
		//	if this returns a promise, warn
		
		return output!
	}

	
	@MainActor	//	run all js on main thread
	public func CallAsync(_ functionAndArgs:String) async throws -> String
	{
		let JavascriptPromise = try Call(functionAndArgs)
		
		var SwiftPromise : Future<String,Error>.Promise? = nil
		
		//	create a future and capture the promise
		let SwiftFuture = Future<String,Error>()
		{
			promise in
			SwiftPromise = promise
			//promise(Result.success("Hello")
		}
		
		//	add js callbacks for .then and .catch and fulfill the promise
		//SwiftPromise!(Result.success("Hello"))
		let onFulfilled: @convention(block) (JSValue) -> Void =
		{
			value in
			let ValueString = value.toString() ?? ""
			SwiftPromise!(Result.success(ValueString))
		}
		
		let onRejected: @convention(block) (JSValue) -> Void =
		{
			value in
			let ValueError = JavascriptError( value.toString() )
			SwiftPromise!(Result.failure( ValueError ) )
			//let error = NSError(domain: key, code: 0, userInfo: [NSLocalizedDescriptionKey : "\($0)"])
			//continuation.resume(throwing: error)
			//continuation.resume(throwing: JavascriptError("async exception") )
		}
		
		let promiseArgs = [unsafeBitCast(onFulfilled, to: JSValue.self), unsafeBitCast(onRejected, to: JSValue.self)]
		
		//	chain promise with .then() and .catch()
		JavascriptPromise.invokeMethod("then", withArguments: promiseArgs)
		
		/*
		let quadruple: @convention(block) (Int) -> Int = { input in
			return input * 4
		}
		context.setObject(quadruple, forKeyedSubscript: "quadruple" as NSString)
		 */
		
		
		//return await SwiftPromise
				
		if #available(macOS 12.0, *)
		{
			let Result = try await SwiftFuture.value
			return Result
		}
		else
		{
			throw JavascriptError("Require macos 12 and above")
		}
		
		/*
		//	check result is a Promise
		return try await withCheckedThrowingContinuation{
			continuation in
			
			//continuation.resume(returning: "Hello")
			
			let onFulfilled: @convention(block) (JSValue) -> Void =
			{
				continuation.resume(returning: "Result")
			}
			
			let onRejected: @convention(block) (JSValue) -> Void =
			{
				//let error = NSError(domain: key, code: 0, userInfo: [NSLocalizedDescriptionKey : "\($0)"])
				//continuation.resume(throwing: error)
				//continuation.resume(throwing: JavascriptError("async exception") )
			}
			
			let promiseArgs = [unsafeBitCast(onFulfilled, to: JSValue.self), unsafeBitCast(onRejected, to: JSValue.self)]
			
			//	chain promise with .then() and .catch()
			//Promise.invokeMethod("then", withArguments: promiseArgs)
		}
		 */
	}

}
