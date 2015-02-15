# GlimpseXML

[![Build Status](https://travis-ci.org/glimpseio/GlimpseXML.svg?branch=master)](https://travis-ci.org/glimpseio/GlimpseXML)

Fast DOM parser & serializer in pure Swift for iOS & Mac

### Parsing & XPath Example

````swift
import GlimpseXML

let music = "~/Music/iTunes/iTunes Music Library.xml".stringByExpandingTildeInPath
let parsed = GlimpseXML.Document.parseFile(music)
switch parsed {
    case .Error(let err):
        println("Error: \(err)")

    case .Value(let val):
        let doc: Document = val.value

        let rootNodeName: String? = doc.rootElement.name
        println("Library Type: \(rootNodeName)")

        let trackCount = doc.xpath("/plist/dict/key[text()='Tracks']/following-sibling::dict/key").value?.first?.text
        println("Track Count: \(trackCount)")

        let dq = doc.xpath("//key[text()='Artist']/following-sibling::string[text()='Bob Dylan']").value?.count
        println("Dylan Quotient: \(dq)")
}
````

### Generating & Serializing Example

You can manually create an XML DOM using `Glimpse.XML` Node elements. Convenience constructors are provided
in order to make tree construction naturally fit the hierarchy of an XML document.

````swift
import GlimpseXML

let node = Node(name: "library", attributes: [("url", "glimpse.io")], children: [
    Node(name: "inventory", children: [
        Node(name: "book", attributes: [("checkout", "true")], children: [
            Node(name: "title", text: "I am a Bunny" ),
            Node(name: "author", text: "Richard Scarry"),
            ]),
        Node(name: "book", attributes: [("checkout", "false")], children: [
            Node(name: "title", text: "You were a Bunny" ),
            Node(name: "author", text: "Scarry Richard"),
            ]),
        ]),
    ])
````

You can also serialize the node to a String:

````swift
let compact: String = node.serialize()
println(compact)
````

Yielding:

````xml
<library url="glimpse.io"><inventory><book checkout="true"><title>I am a Bunny</title><author>Richard Scarry</author></book><book checkout="false"><title>You were a Bunny</title><author>Scarry Richard</author></book></inventory></library>
````

With formatting:

````swift
let formatted: String = node.serialize(indent: true)
println(formatted)
````

````xml
<library url="glimpse.io">
  <inventory>
    <book checkout="true">
      <title>I am a Bunny</title>
      <author>Richard Scarry</author>
    </book>
    <book checkout="false">
      <title>You were a Bunny</title>
      <author>Scarry Richard</author>
    </book>
  </inventory>
</library>
````

You can also include a doc header with an encoding by wrapping the Node in a Document:

````swift
let doc = Document(root: node)
let encoded: String = doc.serialize(indent: true, encoding: "ISO-8859-1")
println(encoded)
````

Which will output:

````xml
<?xml version="1.0" encoding="ISO-8859-1"?>
<library url="glimpse.io">
  <inventory>
    <book checkout="true">
      <title>I am a Bunny</title>
      <author>Richard Scarry</author>
    </book>
    <book checkout="false">
      <title>You were a Bunny</title>
      <author>Scarry Richard</author>
    </book>
  </inventory>
</library>
````

### Setting up GlimpseXML

`GlimpseXML` is a single cross-platform iOS & Mac Framework. To set it up in your project, simply add it as a github submodule, drag the `GlimpseXML.xcodeproj` into your own project file, add `GlimpseXML.framework` to your target's dependencies, and `import GlimpseXML` from any Swift file that should use it.

**Set up Git submodule**

1. Open a Terminal window
1. Change to your projects directory `cd /path/to/MyProject`
1. If this is a new project, initialize Git: `git init`
1. Add the submodule: `git submodule add https://github.com/glimpseio/GlimpseXML.git GlimpseXML`.

**Set up Xcode**

1. Find the `GlimpseXML.xcodeproj` file inside of the cloned GlimpseXML project directory.
1. Drag & Drop it into the `Project Navigator` (⌘+1).
1. Select your project in the `Project Navigator` (⌘+1).
1. Select your target.
1. Select the tab `Build Phases`.
1. Expand `Link Binary With Libraries`.
1. Add `GlimpseXML.framework`
1. Add `import GlimpseXML` to the top of your Swift source files.

