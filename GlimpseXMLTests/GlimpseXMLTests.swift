//
//  GlimpseXMLTests.swift
//  GlimpseXMLTests
//
//  Created by Marc Prud'hommeaux on 10/13/14.
//  Copyright (c) 2014 glimpse.io. All rights reserved.
//

import GlimpseXML
import XCTest

class GlimpseXMLTests: XCTestCase {

    func testXMLParsing() {
        let xml = "<?xml version=\"1.0\" encoding=\"gbk\"?>\n<res><body><msgtype>12</msgtype><langflag>zh_CN</langflag><engineid>1</engineid><tokensn>1000000001</tokensn><dynamicpass>111111</dynamicpass><emptyfield/></body></res>\n"


        let doc = Document()
        let parsed2 = Document.parseString(xml)

        if let value = parsed2.value {
            XCTAssertEqual(xml, value.serialize(indent: false, encoding: nil) ?? "")
            XCTAssertNotEqual(xml, value.serialize(indent: true, encoding: nil) ?? "")
        }
    }

    func testXMLParseErrors() {
        let parsed1 = Document.parseString("<xmlXXX>foo</xml>")
        XCTAssertEqual(parsed1.description, "error: Parser Fatal [1:21]: Opening and ending tag mismatch: xmlXXX line 1 and xml\n")
    }

    func testNamespaces() {
        let ns = Namespace(href: "http://www.exmaple.com", prefix: "ex")
        XCTAssertEqual("<nd/>", Node(name: "nd").serialize())
        XCTAssertEqual("<nd>hello</nd>", Node(name: "nd", text: "hello").serialize())
        XCTAssertEqual("<ex:nd>hello</ex:nd>", Node(name: "nd", namespace: ns, text: "hello").serialize())
        XCTAssertEqual("<ex:nd><child>goodbye</child></ex:nd>", Node(name: "nd", namespace: ns, text: "will be clobbered", children: [Node(name: "child", text: "goodbye")]).serialize())


        let node = Node(name: "foo")
        node.text = "bar"
        XCTAssertEqual("<foo>bar</foo>", node.serialize())

        node.name = "stuff"
        node.text = "x >= y &amp; a < b"

        node["attr1"] = "val1"
        XCTAssertEqual("val1", node["attr1"] ?? "")

        node["attr1"] = nil
        XCTAssertNil(node["attr1"])

        node["attr1"] = "val2"
        XCTAssertEqual("val2", node["attr1"] ?? "")

        node.updateAttribute("attrname", value: "attrvalue", namespace: ns)

        XCTAssertEqual("<stuff attr1=\"val2\" ex:attrname=\"attrvalue\">x &gt;= y &amp; a &lt; b</stuff>", node.serialize())

        node.children = [ Node(name: "child1"), Node(name: "child2", text: "Child Contents") ]
        XCTAssertEqual("<stuff attr1=\"val2\" ex:attrname=\"attrvalue\"><child1/><child2>Child Contents</child2></stuff>", node.serialize())

        let doc = Document(root: node)
        XCTAssertEqual(1, doc.xpath("/stuff/child1").value?.count ?? -1)

        XCTAssertNotNil(ns)
    }

    func testXMLTree() {

        XCTAssertEqual(Node(name: "parent", text: "Text Content").serialize(), Node(name: "parent", children: [ Node(text: "Text Content") ]).serialize())

        var fname, lname: Node?

        let rootNode = Node(name: "company", attributes: [("name", "impathic")], children: [
            Node(name: "employees", children: [
                Node(name: "employee", attributes: [("active", "true")], children: [
                    fname <- Node(name: "firstName", text: "Marc" ),
                    lname <- Node(name: "lastName", text: "Prud'hommeaux"),
                    ]),
                Node(name: "employee", children: [
                    Node(name: "firstName", children: [ Node(text: "Emily") ]),
                    Node(name: "lastName", text: "Tucker"),
                    ]),
                ]),
            ])

        XCTAssertEqual("<company name=\"impathic\"><employees><employee active=\"true\"><firstName>Marc</firstName><lastName>Prud'hommeaux</lastName></employee><employee><firstName>Emily</firstName><lastName>Tucker</lastName></employee></employees></company>", rootNode.serialize())

        XCTAssertEqual(1, fname?.children.count ?? -1)
        XCTAssertEqual(1, lname?.children.count ?? -1)

        XCTAssertEqual(1, rootNode.xpath("//company").value?.count ?? -1)
        XCTAssertEqual(1, rootNode.xpath("../company").value?.count ?? -1)
        XCTAssertEqual(2, rootNode.xpath("./employees/employee").value?.count ?? -1)

        XCTAssertEqual("employee", fname?.parent?.name ?? "<null>")
        XCTAssertEqual("true", fname?.parent?["active"] ?? "<null>")

        fname?.name = "fname"
        fname?.text = "Markus"
        fname?.parent?["active"] = nil

        fname?.parent?.next?.children.first?.name = "fname"

        XCTAssertTrue(fname == fname?.parent?.children.first, "tree traversal of nodes should equate")
        XCTAssertFalse(fname === fname?.parent?.children.first, "tree traversal of nodes are not identical")

        XCTAssertEqual("<company name=\"impathic\"><employees><employee><fname>Markus</fname><lastName>Prud'hommeaux</lastName></employee><employee><fname>Emily</fname><lastName>Tucker</lastName></employee></employees></company>", rootNode.serialize())


        // assign the node to a new Document
        XCTAssertNil(rootNode.document)
        let doc = Document(root: rootNode)
        XCTAssertNotNil(rootNode.document)
        if let nodeDoc = rootNode.document {
            XCTAssertEqual(doc, nodeDoc)
            XCTAssertFalse(doc === nodeDoc, "nodes should not have been identical")

            XCTAssertEqual(doc.rootElement, rootNode)
            XCTAssertFalse(doc.rootElement === rootNode, "nodes should not have been identical")
        }

        XCTAssertEqual("<?xml version=\"1.0\" encoding=\"utf8\"?>\n<company name=\"impathic\"><employees><employee><fname>Markus</fname><lastName>Prud'hommeaux</lastName></employee><employee><fname>Emily</fname><lastName>Tucker</lastName></employee></employees></company>\n", doc.serialize())

        // swap order of employees
        fname?.parent?.next?.next = fname?.parent?

        XCTAssertEqual("<?xml version=\"1.0\" encoding=\"utf8\"?>\n<company name=\"impathic\"><employees><employee><fname>Emily</fname><lastName>Tucker</lastName></employee><employee><fname>Markus</fname><lastName>Prud'hommeaux</lastName></employee></employees></company>\n", doc.serialize())

        // swap back
        fname?.parent?.prev?.prev = fname?.parent?
        XCTAssertEqual("<?xml version=\"1.0\" encoding=\"utf8\"?>\n<company name=\"impathic\"><employees><employee><fname>Markus</fname><lastName>Prud'hommeaux</lastName></employee><employee><fname>Emily</fname><lastName>Tucker</lastName></employee></employees></company>\n", doc.serialize())

        let parse3 = Document.parseString(doc.serialize())
        if let doc3 = parse3.value {
            XCTAssertEqual(doc3.serialize(indent: true), doc.serialize(indent: true))
        } else {
            XCTFail(parse3.error!.description)
        }

        XCTAssertEqual(1, doc.xpath("//company").value?.count ?? -1)
        XCTAssertEqual(1, doc.xpath("//company[@name = 'impathic']").value?.count ?? -1)
        XCTAssertEqual(1, doc.xpath("//employees").value?.count ?? -1)
        XCTAssertEqual(2, doc.xpath("//employee").value?.count ?? -1)
        XCTAssertEqual(2, doc.xpath("/company/employees/employee").value?.count ?? -1)
        XCTAssertEqual(1, doc.xpath("/company/employees/employee/fname[text() != 'Emily']").value?.count ?? -1)
        XCTAssertEqual(1, doc.xpath("/company/employees/employee/fname[text() = 'Emily']").value?.count ?? -1)
        XCTAssertEqual(1, doc.xpath("/company/employees/employee/fname[text() = 'Markus']").value?.count ?? -1)


        XCTAssertEqual(2, fname?.parent?.xpath("../employee").value?.count ?? -1)
        XCTAssertEqual(2, fname?.parent?.xpath("../..//employee").value?.count ?? -1)
        XCTAssertEqual(1, fname?.parent?.xpath("./fname[text() = 'Markus']").value?.count ?? -1)

        XCTAssertEqual("XPath Error [0:0]: ", doc.xpath("+").error?.description ?? "NOERROR")

        doc.xpath("/company/employees/employee/fname[text() = 'Emily']").value?.first?.text = "Emilius"

        XCTAssertEqual(0, doc.xpath("/company/employees/employee/fname[text() = 'Emily']").value?.count ?? -1)

        XCTAssertEqual("<?xml version=\"1.0\" encoding=\"utf8\"?>\n<company name=\"impathic\"><employees><employee><fname>Markus</fname><lastName>Prud'hommeaux</lastName></employee><employee><fname>Emilius</fname><lastName>Tucker</lastName></employee></employees></company>\n", doc.serialize())

        doc.xpath("/company").value?.first? += Node(name: "descriptionText", children: [
            Node(text: "This is a super awesome company! It is > than the others & it is cool too!!")
            ])

        doc.xpath("/company").value?.first? += Node(name: "descriptionData", children: [
            Node(cdata: "This is a super awesome company! It is > than the others & it is cool too!!"),
            ])

        XCTAssertEqual("<?xml version=\"1.0\" encoding=\"utf8\"?>\n<company name=\"impathic\"><employees><employee><fname>Markus</fname><lastName>Prud'hommeaux</lastName></employee><employee><fname>Emilius</fname><lastName>Tucker</lastName></employee></employees><descriptionText>This is a super awesome company! It is &gt; than the others &amp; it is cool too!!</descriptionText><descriptionData><![CDATA[This is a super awesome company! It is > than the others & it is cool too!!]]></descriptionData></company>\n", doc.serialize())
    }

    func testUnicodeEncoding() {
        // from http://www.lookout.net/2011/06/special-unicode-characters-for-error.html

        /// The Byte Order Mark U+FEFF is a special character defining the byte order and endianess of text data.
        let uBOM = "\u{FEFF}"

        /// The Right to Left Override U+202E defines special meaning to re-order the
        /// display of text for right-to-left reading.
        let uRLO = "\u{202E}"

        /// Mongolian Vowel Separator U+180E is invisible and has the whitespace property.
        let uMVS = "\u{180E}"

        /// Word Joiner U+2060 is an invisible zero-width character.
        let uWordJoiner = "\u{2060}"

        /// A reserved code point U+FEFE
        let uReservedCodePoint = "\u{FEFE}"

        /// The code point U+FFFF is guaranteed to not be a Unicode character at all
        let uNotACharacter = "\u{FFFF}"

        /// An unassigned code point U+0FED
        let uUnassigned = "\u{0FED}"

        /// An illegal low half-surrogate U+DEAD
//        let uDEAD = "\u{DEAD}"

        /// An illegal high half-surrogate U+DAAD
//        let uDAAD = "\u{DAAD}"

        /// A Private Use Area code point U+F8FF which Apple happens to use for its logo.
        let uPrivate = "\u{F8FF}"

        /// U+FF0F FULLWIDTH SOLIDUS should normalize to / in a hostname
        let uFullwidthSolidus = "\u{FF0F}"

        /// Code point with a numerical mapping and value U+1D7D6 MATHEMATICAL BOLD DIGIT EIGHT
//        let uBoldEight = char.ConvertFromUtf32(0x1D7D6);

        /// IDNA2003/2008 Deviant - U+00DF normalizes to "ss" during IDNA2003's mapping phase,
        /// different from its IDNA2008 mapping.
        /// See http://www.unicode.org/reports/tr46/
        let uIdnaSs = "\u{00DF}"

        /// U+FDFD expands by 11x (UTF-8) and 18x (UTF-16) under NFKC/NFKC
        let uFDFA = "\u{FDFA}"

        /// U+0390 expands by 3x (UTF-8) under NFD
        let u0390 = "\u{0390}"

        /// U+1F82 expands by 4x (UTF-16) under NFD
        let u1F82 = "\u{1F82}"

        /// U+FB2C expands by 3x (UTF-16) under NFC
        let uFB2C = "\u{FB2C}"

        /// U+1D160 expands by 3x (UTF-8) under NFC
//        let u1D160 = char.ConvertFromUtf32(0x1D160);

        let chars = [
            "ABC",
            "👀 💝 🐱",
            uBOM,
            uRLO, // cool: <emojis></emojis>
            uMVS,
            uWordJoiner,
            uReservedCodePoint,
//            uNotACharacter, // "Parser Fatal [2:9]: PCDATA invalid Char value 65535"
            uUnassigned,
            uPrivate,
            uFullwidthSolidus,
            uIdnaSs,
            uFDFA,
            u0390,
            u1F82,
            uFB2C,
        ]
        let allChars = chars.reduce("", combine: +) // concatination of all of the above

        for chars in chars + [allChars] {
            let doc = Document(root: Node(name: "blah", text: chars))
            // "latin1" error: "encoding error : output conversion failed due to conv error, bytes 0x00 0x3F 0x78 0x6D I/O error : encoder error"
            let data = doc.serialize(encoding: "utf8")
            XCTAssertTrue((data as NSString).containsString(chars))
            // println("data: [\(data.lengthOfBytesUsingEncoding(NSUTF8StringEncoding))] \(data)")

            let parsed = Document.parseString(data)
            if let parsedDoc = parsed.value {
                XCTAssertEqual(1, doc.xpath("//blah[text() = '\(chars)']").value?.count ?? -1)
            } else {
                XCTFail(parsed.error!.description)
            }
        }
    }

    // enable this to run a perpetual memory profiline test
    func DISABLEDtestLoadTestsProfiling() {
        for _ in 1...999999 {
            autoreleasepool({ [unowned self] () -> () in
                self.testLoadLibxmlTests()
            })
        }
    }

    /// Tests all the xml test files from libxml, assuming it is located at ../../ext/libxml
    func testLoadLibxmlTests() {

        let dir = __FILE__.stringByDeletingLastPathComponent + "/../../../ext/libxml/test"

        if let enumerator = NSFileManager.defaultManager().enumeratorAtPath(dir) {
            let files: NSArray = enumerator.allObjects.map({ "\(dir)/\($0)" }).filter({ $0.hasSuffix(".xml") })

            // concurrent enumeration will veryify that the tests work
            files.enumerateObjectsWithOptions(.Concurrent, usingBlock: { (file, index, keepGoing) -> Void in
                let doc = Document.parseFile(file as String)
                let nodes = doc.value?.xpath("//*")
                // println("parsed \(file) nodes: \(nodes?.value?.count ?? -1) error: \(doc.error)")
                if let nodes = nodes?.value {
                    XCTAssert(nodes.count > 0)
                }
            })
        } else {
            XCTFail("no libxml test files found")
        }
    }
}


/// assign the given field to the given variable, just like "=" except that the assignation is returned by the function: “Unlike the assignment operator in C and Objective-C, the assignment operator in Swift does not itself return a value”
private func <- <T>(inout assignee: T?, assignation: T) -> T {
    assignee = assignation
    return assignation
}
infix operator <- {}


