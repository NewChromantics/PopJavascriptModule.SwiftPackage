// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.


import PackageDescription



let package = Package(
	name: "PopJavascriptModule",
	
	platforms: [
		.iOS(.v15),
		.macOS(.v13)	//	regex in macos 13+
	],
	

	products: [
		.library(
			name: "PopJavascriptModule",
			targets: [
				"PopJavascriptModule"
			]),
	],
	targets: [

		.target(
			name: "PopJavascriptModule",
			dependencies: []
		)
	]
)
