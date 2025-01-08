import Foundation

//	from https://github.com/NewChromantics/PopEngine/blob/master/src/JavascriptConvertImports.cpp

//	Popengine implements require() which makes an exports symbol for the module
//	and returns it (a module)
//	so imports need changing, and exports inside a file need converting

//	convert imports;
//		import * as Module from 'filename1'
//		import symbol from 'filename2'
//		import { symbol } from 'filename3'
//		import { symbol as NewSymbol } from 'filename4'
//	into
//		const Module = require('filename1')
//
//		const ___PrivateModule = require('filename2')
//		const symbol = ___PrivateModule.symbol;
//
//		const ___PrivateModule = require('filename3')
//		const symbol = ___PrivateModule.symbol;
//
//		const ___PrivateModule = require('filename4')
//		const NewSymbol = ___PrivateModule.symbol;


//	make a pattern for valid js symbols
let SymbolChars = "a-zA-Z0-9_";
//let Symbol = "[\(SymbolChars)]+";
let SymbolAndWhitespace = "[a-zA-Z0-9_\\s]+";
let Whitespace = "\\s+";
let OptionalWhitespace = "\\s*";
let Quote = "[\\\"'`]"

//	gr: need a prefix so we dont match
//		sexport
//	but anything not-symbolly can be before
let ExportPrefix = "^|[^\(SymbolChars)]"

//	sometimes the symbol we're exporting is NOT the last symbol
//	export default class MyExport extends NotMyExport
let PostSymbolKeywords = ["extends"]

//	must be other cases... like new line and symbol? maybe we can use ^symbol ?
//	symbol( <-- function
//	symbol= <-- var definition
//	symbol; <-- var declaration
//	symbol{ <-- class
//	gr: extends in here doesn't work, because we grab all a-z symbols before it
//		we could remove it here, now caught via PostSymbolKeywords
let VariableNameEnd = "\\(|=|$|\\n|;|extends|\\{";


func regexp_matches(_ text:String, _ pattern:String!, caseSensitive:Bool) throws -> [NSTextCheckingResult]
{
	do 
	{
		let options = caseSensitive ? NSRegularExpression.Options() : NSRegularExpression.Options.caseInsensitive
		
		let regex = try NSRegularExpression(pattern: pattern, options: options)
		let nsString = text as NSString

		//	gr: this happens when line feeds are /r/n! (and probably ascii/utf)
		if ( nsString.length != text.count )
		{
			throw JavascriptError("String as NSString is different length to swift string, and is going to produce bad results")
		}
		
		let SearchRange = NSMakeRange(0, nsString.length)
		//let SearchRange = NSMakeRange(0, text.count)
		let results = regex.matches(in: text,options: [], range:SearchRange )
	
		return results
	}
	catch let error as NSError
	{
		throw JavascriptError("invalid regex: \(error.localizedDescription)")
	}
}

extension String
{
	func idx(_ index:Int) -> String.Index {
		let str = self
		return str.index(str.startIndex, offsetBy: index)/*Upgraded to swift 3-> was: startIndex.advancedBy*/
	}
}

func strRange(_ str:String,_ i:Int, len:Int)->Range<String.Index>
{
	let startIndex:String.Index = str.idx(i)
	let endIndex:String.Index = str.idx(i + len/* + 1*/)//+1 because swift 3 upgrade doesn't allow ... ranges
	let range = startIndex..<endIndex//swift 3 upgrade was-> startIndex...endIndex
	return range/*longhand -> Range(start: startIndex,end: endIndex)*/
}
func GetSubString( _ string:String, start:Int, length:Int) throws -> String
{
	if ( start < 0 )
	{
		throw JavascriptError("Substring out of range")
	}

	if ( start+length >= string.count )
	{
		throw JavascriptError("Substring out of range")
	}

	let lastIndex = start+length
	let stringStart = string.index( string.startIndex, offsetBy: start )
	let stringEnd = string.index( string.startIndex, offsetBy: start+length-1 )
	let range = string[stringStart...stringEnd]
	let returnString = String(range)

	return returnString
}


func StringFromRange(_ Haystack:String, needle:NSRange) throws -> String
{
	if ( needle.length == 0 )
	{
		return ""
	}
	return try GetSubString( Haystack, start: needle.location, length: needle.length )
}

typealias Replacer = (_ match:String, _ captures:[String]) throws -> String

func string_replace_regex(_ immutablestr:String, pattern:String, caseSensitive:Bool,replacer:Replacer) throws -> String
{
	var str = immutablestr
	//	gr: need to process in reverse, as the original string needs to be modified backwards
	let matches = try regexp_matches(str, pattern, caseSensitive: caseSensitive).reversed()
	matches.forEach()
	{
		match in
		
		let LineRange = match.range(at:0)
		let Line = try! StringFromRange( str, needle: LineRange )
		let CaptureCount = match.numberOfRanges-1
		var Captures : [String] = []
		for CaptureIndex in 0...CaptureCount-1
		{
			let CaptureRange = match.range(at:1+CaptureIndex)
			let Capture = try! StringFromRange( str, needle:CaptureRange )
			Captures.append( Capture )
		}

		let LineStrRange = strRange(str, LineRange.location, len:LineRange.length)
		let replacment = try! replacer( Line, Captures )
		str.replaceSubrange( LineStrRange, with: replacment)
	}
	return str
}


func string_regex_match_groups(_ str:String, pattern:String, caseSensitive: Bool) throws -> [String]?
{
	var str = str
	//	gr: need to process in reverse, as the original string needs to be modified backwards
	let matches = try regexp_matches(str, pattern, caseSensitive:caseSensitive )
	
	//	expecting only one match
	if ( matches.count != 1 )
	{
		throw JavascriptError("Too many regex matches")
	}
	
	let match = matches[0]
	let LineRange = match.range(at:0)
	let Line = try StringFromRange( str, needle: LineRange )
	let CaptureCount = match.numberOfRanges-1
	var Captures : [String] = []
	for CaptureIndex in 0...CaptureCount-1
	{
		let CaptureRange = match.range(at:1+CaptureIndex)
		let Capture = try StringFromRange( str, needle:CaptureRange )
		Captures.append( Capture )
	}
	return Captures

}



func FilenameToModuleSymbol(_ filename:String, uidSuffix:Int) -> String
{
	var Symbol = filename;
	
	//	replace non-symbol chars with underscores
	let CharacterFilter = "[^a-zA-Z0-9_]"
	let regex = try! NSRegularExpression(pattern: CharacterFilter, options: .caseInsensitive)
	Symbol = regex.stringByReplacingMatches( in: Symbol, options: [], range: NSRange(0..<Symbol.utf16.count), withTemplate: "_")

	return "__Module_Exports_From_\(Symbol)_\(uidSuffix)"
}

struct ImportSymbol
{
	static let Default = "default"
	var importingSymbol : String	//	if null then we use the module's whole export list
	var variable : String
}

extension String 
{
	func trim(trimNewLines:Bool=false) -> String
	{
		return self.trimmingCharacters(in: trimNewLines ? NSCharacterSet.whitespacesAndNewlines : NSCharacterSet.whitespaces)
	}
}

func TrimString(_ str:String) -> String
{
	var Trimmed = str
	Trimmed.trim()
	return Trimmed
}

func ExtractSymbols(_ fullSymbolsString:String,moduleExportsSymbol:String) throws -> [ImportSymbol]
{
	//	gr: this wont work;
	//	import x,{y,z} from 'xyz.js'
	var symbolsString = fullSymbolsString.trim()
	let InsideBraces = symbolsString.starts(with: "{")

	func SplitSingleSymbol(origSymbolString:String) throws -> ImportSymbol
	{
		var symbolString = origSymbolString
		symbolString = symbolString.trim()
		//	if we're not importing symbols, then we are just importing the default
		let ImportingSymbols = InsideBraces
		symbolString = symbolString.trimmingCharacters(in: ["{","}"])

		//	are we renaming the imported symbol?
		//	x as y
		//	* as z
		//	*
		//	abc
		let SplitByAs = symbolString.components(separatedBy:" as ").map(TrimString)
		if ( SplitByAs.count > 2 )
		{
			throw JavascriptError("import symbol with as, split more than once")
		}
		
		var ImportingSymbol = SplitByAs[0]
		if ( ImportingSymbol == "*" )
		{
			ImportingSymbol = "\(moduleExportsSymbol)"
		}
		else if ( InsideBraces )
		{
			ImportingSymbol = "\(moduleExportsSymbol).\(ImportingSymbol)"
		}
		else
		{
			ImportingSymbol = "\(moduleExportsSymbol).\(ImportSymbol.Default)"
		}

		var Variable = ImportingSymbol
		if ( SplitByAs.count == 2 )
		{
			Variable = SplitByAs[1]
		}
		else
		{
			Variable = SplitByAs[0]
		}
		
		return ImportSymbol(importingSymbol: ImportingSymbol, variable: Variable)
	}
	
	var SymbolStrings = symbolsString.components(separatedBy: [","])
	return try SymbolStrings.map(SplitSingleSymbol)
}


func ConvertImports(Source:String,importFunctionName:String,replacementNewLines:Bool) throws -> String
{
	//	gr: we can probably reduce this down to one regex
	//	import<symbols>from<script><instruction end>
	if #available(macOS 13.0, *) 
	{
		let ImportPattern = "import(.+)from\(OptionalWhitespace)\(Quote){1}(.+)\(Quote){1}"

		//	to make some things simpler when importing the same file, but don't want conflicting symbols, add a counter
		var ImportCounter = 0
		func ImportReplacement(match:String,captures:[String]) throws -> String
		{
			let SymbolsString = captures[0];
			let Filename = captures[1]
			let ModuleSymbol = FilenameToModuleSymbol(Filename,uidSuffix:ImportCounter)
			let Symbols = try ExtractSymbols( SymbolsString, moduleExportsSymbol: ModuleSymbol )
			
			//print("Matched \(match)<----")
			//print("  Symbols=\(SymbolsString)<----")
			//print("  ExtractedSymbols=\(Symbols)<----")
			//print("  Filename=\(captures[1])<----")
			
			let ModuleObjectReplacement = "const \(ModuleSymbol) = \(JavascriptModule.ImportModuleFunctionSymbol)(`\(Filename)`);"
			//print("  ModuleObjectReplacement=\(ModuleObjectReplacement)<----")
			
			var ReplacementString = ""
			ReplacementString += "/*\(match)*/\n"
			
			ReplacementString += ModuleObjectReplacement
			if ( replacementNewLines )
			{
				ReplacementString += "\n"
			}
			
			for symbol in Symbols
			{
				ReplacementString += "const \(symbol.variable) = \(symbol.importingSymbol); "
				if ( replacementNewLines )
				{
					ReplacementString += "\n"
				}
			}
			//print(ReplacementString+"\n\n")

			ImportCounter += 1
			
			return ReplacementString
		}
		
		var ES5Source = try string_replace_regex( Source, pattern: ImportPattern, caseSensitive: true, replacer: ImportReplacement )
		return ES5Source
	}
	else
	{
		throw JavascriptError("No regex")
	}

}


//	export let A = B;		let A = ... exports.A = A;
//	export function C(...
//	export const D;
//	export
func ConvertExports(Source:String,exportSymbolName:String,replacementNewLines:Bool) -> String
{
	var ExportedSymbols:[ImportSymbol]=[]
	
	
	func ExportReplacement(match:String,captures:[String]) throws -> String
	{
		let Prefix = captures[0]
		let KeywordsAndSymbol = captures[1].trim(trimNewLines:true)
		let VariableEnd = captures[2]
		
		//	gr: very very special case, in my dictionary we detect the word export in a string
		//		followed by the next word in the dictionary exportability (and then 10,000 more words)
		//	todo: proper fix is to catch when export xyz is inside a string and not convert it
		//	gr: this word is sometimes different, so look out for export export
		if ( KeywordsAndSymbol.starts(with: "export") )
		{
			//	don't change input
			return match
		}
		
		var Keywords = KeywordsAndSymbol.components(separatedBy: .whitespacesAndNewlines)
		
		//	gr: there are some cases where a keyword comes AFTER the symbol
		func IsPostSymbolKeyword(_ match:String) -> Bool
		{
			return PostSymbolKeywords.contains(match)
		}
		var PostSymbolIndex = Keywords.firstIndex(where: IsPostSymbolKeyword) ?? (Keywords.count)
		var Symbol = Keywords[PostSymbolIndex-1]
		
		var HasDefault = Keywords.filter{ $0 == "default" }.count != 0
		var KeywordsWithoutDefault = Keywords.filter{ $0 != "default" }
		var OutputKeywords = KeywordsWithoutDefault.joined(separator: " ")

		ExportedSymbols.append( ImportSymbol(importingSymbol: Symbol, variable: HasDefault ? ImportSymbol.Default : Symbol ) )
	
		//var Output = "/*\(match)*/\n"
		var Output = ""
		Output += "\(Prefix) \(OutputKeywords) \(VariableEnd)"
		return Output
	}
	

	//	gr: we can't really filter keywords here properly
	//		as we can't nicely match a group over & over (will only grab last)
	//	so grab EVERYTHING up to a break
	let ExportPattern = "(\(ExportPrefix))export\(Whitespace)(\(SymbolAndWhitespace))(\(VariableNameEnd))"
	
	var ES5Source = try! string_replace_regex( Source, pattern: ExportPattern, caseSensitive: true, replacer: ExportReplacement )

	//	now output all the symbols we found
	ES5Source += "\n //\texports found\n"
	for exportedSymbol in ExportedSymbols
	{
		ES5Source += "\(exportSymbolName).\(exportedSymbol.variable) = \(exportedSymbol.importingSymbol);"
		ES5Source += "\n"
	}
	
	return ES5Source
}


//	convert ES6 imports to custom import & export symbols
public func RewriteES6ImportsAndExports(_ originalScript:String,importFunctionName:String,exportSymbolName:String,replacementNewLines:Bool=false) -> String
{
	var Source = originalScript
	Source = try! ConvertImports(Source:Source, importFunctionName:importFunctionName, replacementNewLines:replacementNewLines )
	Source = try! ConvertExports(Source: Source, exportSymbolName:exportSymbolName, replacementNewLines:replacementNewLines )
	return Source
}
