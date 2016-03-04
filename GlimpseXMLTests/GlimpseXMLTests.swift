//
//  GlimpseXMLTests.swift
//  GlimpseXMLTests
//
//  Created by Marc Prud'hommeaux on 10/13/14.
//  Copyright (c) 2014 glimpse.io. All rights reserved.
//

import GlimpseXML
import XCTest

/// Temporary (hopefully) shims for XCTAssert methods that can accept throwables
extension XCTestCase {
    /// Same as XCTAssertEqual, but handles throwable autoclosures
    func XCTAssertEqualX<T: Equatable>(@autoclosure v1: () throws -> T, @autoclosure _ v2: () throws -> T, file: String = __FILE__, line: UInt = __LINE__) {
        do {
            let x1 = try v1()
            let x2 = try v2()
            if x1 != x2 {
                XCTFail("Not equal", file: file, line: line)
            }
        } catch {
            XCTFail(String(error), file: file, line: line)
        }
    }
}

class GlimpseXMLTests: XCTestCase {

    func testXMLParsing() {
        let xml = "<?xml version=\"1.0\" encoding=\"gbk\"?>\n<res><body><msgtype>12</msgtype><langflag>zh_CN</langflag><engineid>1</engineid><tokensn>1000000001</tokensn><dynamicpass>111111</dynamicpass><emptyfield/></body></res>\n"

        do {
            let value = try Document.parseString(xml)

            XCTAssertEqual(xml, value.serialize(indent: false, encoding: nil) ?? "")
            XCTAssertNotEqual(xml, value.serialize(indent: true, encoding: nil) ?? "")
        } catch {
            XCTFail(String(error))
        }
    }

    func testHTMLParsing() {
        let html = "<html><head><title>Some HTML!</title><body><p>Some paragraph<br>Another Line</body></html>" // malformed

        do {
            let value = try Document.parseString(html, html: true)

            XCTAssertEqual("<?xml version=\"1.0\" standalone=\"yes\"?>\n<!DOCTYPE html PUBLIC \"-//W3C//DTD HTML 4.0 Transitional//EN\" \"http://www.w3.org/TR/REC-html40/loose.dtd\">\n<html><head><title>Some HTML!</title></head><body><p>Some paragraph<br/>Another Line</p></body></html>\n", value.serialize(indent: false, encoding: nil) ?? "")
        } catch {
            XCTFail(String(error))
        }
    }

    func testXMLParseDemo() {
        // iTunes Library Location <http://support.apple.com/en-us/HT201610>
        let music = ("~/Music/iTunes/iTunes Music Library.xml" as NSString).stringByExpandingTildeInPath
        if !NSFileManager.defaultManager().fileExistsAtPath(music) { return }

        do {
            let doc = try GlimpseXML.Document.parseFile(music)
            let rootNodeName: String? = doc.rootElement.name
            print("Library Type: \(rootNodeName)")

            let trackCount = try doc.xpath("/plist/dict/key[text()='Tracks']/following-sibling::dict/key").first?.text
            print("Track Count: \(trackCount)")

            let dq = try doc.xpath("//key[text()='Artist']/following-sibling::string[text()='Bob Dylan']").count
            print("Dylan Quotient: \(dq)")
        } catch {
            XCTFail(String(error))
        }
    }

    func testXMLWriteDemo() {

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

        let compact: String = node.serialize()
        //print(compact)
        XCTAssertFalse(compact.isEmpty)

        let formatted: String = node.serialize(indent: true)
        //print(formatted)
        XCTAssertFalse(formatted.isEmpty)

        let doc = Document(root: node)
        let encoded: String = doc.serialize(indent: true, encoding: "ISO-8859-1")
        //print(encoded)
        XCTAssertFalse(encoded.isEmpty)
    }

    func testXMLParseErrors() {
        do {
            let _ = try Document.parseString("<xmlXXX>foo</xml>")
            XCTFail("Should have thrown exception")
        } catch {
            if let error = error as? CustomDebugStringConvertible {
                XCTAssertEqual(error.debugDescription, "Parser Fatal [1:21]: Opening and ending tag mismatch: xmlXXX line 1 and xml\n")
            } else {
                XCTFail("Error was not CustomDebugStringConvertible")
            }
        }
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
        XCTAssertEqualX(1, try doc.xpath("/stuff/child1").count ?? -1)

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

//        XCTAssertEqualX(1, try rootNode.xpath("//company").count)
//        XCTAssertEqualX(1, try rootNode.xpath("../company").count)
//        XCTAssertEqualX(2, try rootNode.xpath("./employees/employee").count)

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
        fname?.parent?.next?.next = fname?.parent

        XCTAssertEqual("<?xml version=\"1.0\" encoding=\"utf8\"?>\n<company name=\"impathic\"><employees><employee><fname>Emily</fname><lastName>Tucker</lastName></employee><employee><fname>Markus</fname><lastName>Prud'hommeaux</lastName></employee></employees></company>\n", doc.serialize())

        // swap back
        fname?.parent?.prev?.prev = fname?.parent
        XCTAssertEqual("<?xml version=\"1.0\" encoding=\"utf8\"?>\n<company name=\"impathic\"><employees><employee><fname>Markus</fname><lastName>Prud'hommeaux</lastName></employee><employee><fname>Emily</fname><lastName>Tucker</lastName></employee></employees></company>\n", doc.serialize())

        do {
            let parse3 = try Document.parseString(doc.serialize())
            XCTAssertEqual(parse3.serialize(indent: true), doc.serialize(indent: true))

            XCTAssertEqualX(1, try doc.xpath("//company").count)
            XCTAssertEqualX(1, try doc.xpath("//company[@name = 'impathic']").count)
            XCTAssertEqualX(1, try doc.xpath("//employees").count)
            XCTAssertEqualX(2, try doc.xpath("//employee").count)
            XCTAssertEqualX(2, try doc.xpath("/company/employees/employee").count)
            XCTAssertEqualX(1, try doc.xpath("/company/employees/employee/fname[text() != 'Emily']").count)
            XCTAssertEqualX(1, try doc.xpath("/company/employees/employee/fname[text() = 'Emily']").count)
            XCTAssertEqualX(1, try doc.xpath("/company/employees/employee/fname[text() = 'Markus']").count)


            XCTAssertEqualX(2, try fname?.parent?.xpath("../employee").count ?? -1)
            XCTAssertEqualX(2, try fname?.parent?.xpath("../..//employee").count ?? -1)
            XCTAssertEqualX(1, try fname?.parent?.xpath("./fname[text() = 'Markus']").count ?? -1)

            // XCTAssertEqual("XPath Error [0:0]: ", doc.xpath("+").error?.debugDescription ?? "NOERROR")
            
            try doc.xpath("/company/employees/employee/fname[text() = 'Emily']").first?.text = "Emilius"

            XCTAssertEqualX(0, try doc.xpath("/company/employees/employee/fname[text() = 'Emily']").count)

            XCTAssertEqual("<?xml version=\"1.0\" encoding=\"utf8\"?>\n<company name=\"impathic\"><employees><employee><fname>Markus</fname><lastName>Prud'hommeaux</lastName></employee><employee><fname>Emilius</fname><lastName>Tucker</lastName></employee></employees></company>\n", doc.serialize())

            try doc.xpath("/company").first? += Node(name: "descriptionText", children: [
                Node(text: "This is a super awesome company! It is > than the others & it is cool too!!")
                ])

            try doc.xpath("/company").first? += Node(name: "descriptionData", children: [
                Node(cdata: "This is a super awesome company! It is > than the others & it is cool too!!"),
                ])

            XCTAssertEqual("<?xml version=\"1.0\" encoding=\"utf8\"?>\n<company name=\"impathic\"><employees><employee><fname>Markus</fname><lastName>Prud'hommeaux</lastName></employee><employee><fname>Emilius</fname><lastName>Tucker</lastName></employee></employees><descriptionText>This is a super awesome company! It is &gt; than the others &amp; it is cool too!!</descriptionText><descriptionData><![CDATA[This is a super awesome company! It is > than the others & it is cool too!!]]></descriptionData></company>\n", doc.serialize())
        } catch {
            XCTFail(String(error))
        }
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
        let _ = "\u{FFFF}" // uNotACharacter

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

            do {
                let parsed = try Document.parseString(data)
                XCTAssertEqualX(1, try parsed.xpath("//blah[text() = '\(chars)']").count ?? -1)
            } catch {
                XCTFail(String(error))
            }
        }
    }

    func enumerateLibXMLTests(f: String->Void) {
        let dir = "/opt/src/libxml"

        if let enumerator = NSFileManager.defaultManager().enumeratorAtPath(dir) {
            let files: NSArray = enumerator.allObjects.map({ "\(dir)/\($0)" }).filter({ $0.hasSuffix(".xml") })

            // concurrent enumeration will verify that multi-threaded access works
            files.enumerateObjectsWithOptions(.Concurrent, usingBlock: { (file, index, keepGoing) -> Void in
                f("\(file)")
            })
        } else {
            // XCTFail("no libxml test files found") // it's fine; we don't need to have them
        }
    }

    func XXXtestLoadTestsProfiling() {
        measureBlock { self.testLoadLibxmlTests() }
    }

    /// Tests all the xml test files from libxml
    func testLoadLibxmlTests() {
        let expectFailures = [
            "libxml/os400/iconv/bldcsndfa/ccsid_mibenum.xml",
            "libxml/result/namespaces/err_10.xml",
            "libxml/result/errors/attr1.xml",
            "libxml/result/namespaces/err_11.xml",
            "libxml/result/SVG/bike-errors.xml",
            "libxml/result/valid/t8a.xml",
            "libxml/result/xmlid/id_err1.xml",
            "libxml/result/xmlid/id_err2.xml",
            "libxml/result/xmlid/id_tst1.xml",
            "libxml/result/errors/attr2.xml",
            "libxml/result/xmlid/id_tst2.xml",
            "libxml/result/xmlid/id_tst3.xml",
            "libxml/result/xmlid/id_tst4.xml",
            "libxml/result/valid/index.xml",
            "libxml/doc/examples/tst.xml",
            "libxml/test/errors/attr1.xml",
            "libxml/test/errors/name.xml",
            "libxml/test/errors/attr2.xml",
            "libxml/test/errors/attr4.xml",
            "libxml/test/errors/name2.xml",
            "libxml/test/errors/cdata.xml",
            "libxml/test/errors/charref1.xml",
            "libxml/test/errors/comment1.xml",
            "libxml/test/recurse/lol5.xml",
            "libxml/test/errors/content1.xml",
            "libxml/test/japancrlf.xml",
            "libxml/test/namespaces/err_10.xml",
            "libxml/test/namespaces/err_11.xml",
            "libxml/result/valid/t8.xml",
            "libxml/test/recurse/lol1.xml",
            "libxml/test/recurse/lol2.xml",
            "libxml/result/errors/attr4.xml",
            "libxml/test/recurse/lol4.xml",
            "libxml/test/valid/t8.xml",
            "libxml/test/valid/t8a.xml",
            "libxml/result/errors/cdata.xml",
            "libxml/result/errors/charref1.xml",
            "libxml/result/errors/comment1.xml",
            "libxml/doc/tutorial/includestory.xml",
            "libxml/result/errors/content1.xml",
            "libxml/result/errors/name.xml",
            "libxml/result/errors/name2.xml",
            "libxml/test/recurse/lol6.xml",
            "libxml/os400/iconv/bldcsndfa/ccsid_mibenum.xml",
            "libxml/result/errors/attr1.xml",
            "libxml/result/namespaces/err_10.xml",
            "libxml/result/namespaces/err_11.xml",
            "libxml/result/SVG/bike-errors.xml",
            "libxml/result/errors/attr2.xml",
            "libxml/doc/examples/tst.xml",
            "libxml/result/valid/t8a.xml",
            "libxml/result/xmlid/id_err1.xml",
            "libxml/result/xmlid/id_err2.xml",
            "libxml/result/xmlid/id_tst1.xml",
            "libxml/result/xmlid/id_tst2.xml",
            "libxml/result/xmlid/id_tst3.xml",
            "libxml/result/xmlid/id_tst4.xml",
            "libxml/result/valid/index.xml",
            "libxml/test/errors/name.xml",
            "libxml/test/errors/name2.xml",
            "libxml/test/errors/attr1.xml",
            "libxml/test/errors/attr2.xml",
            "libxml/test/errors/attr4.xml",
            "libxml/test/errors/cdata.xml",
            "libxml/test/errors/charref1.xml",
            "libxml/test/errors/comment1.xml",
            "libxml/test/errors/content1.xml",
            "libxml/test/japancrlf.xml",
            "libxml/test/namespaces/err_10.xml",
            "libxml/test/namespaces/err_11.xml",
            "libxml/test/recurse/lol5.xml",
            "libxml/result/valid/t8.xml",
            "libxml/test/recurse/lol1.xml",
            "libxml/test/recurse/lol2.xml",
            "libxml/test/recurse/lol4.xml",
            "libxml/test/valid/t8.xml",
            "libxml/test/valid/t8a.xml",
            "libxml/doc/tutorial/includestory.xml",
            "libxml/result/errors/attr4.xml",
            "libxml/result/errors/cdata.xml",
            "libxml/result/errors/charref1.xml",
            "libxml/result/errors/comment1.xml",
            "libxml/result/errors/content1.xml",
            "libxml/result/errors/name.xml",
            "libxml/result/errors/name2.xml",
            "libxml/test/recurse/lol6.xml",
        ]
        enumerateLibXMLTests { file in
            do {
                let doc = try Document.parseFile(file)
                let nodes = try doc.xpath("//*")
                // println("parsed \(file) nodes: \(nodes?.count ?? -1) error: \(doc.error)")
                XCTAssert(nodes.count > 0)
            } catch {
                for path in expectFailures {
                    if file.hasSuffix(path) { return }
                }
                XCTFail("XML file should not have failed: \(file)")
            }
        }
    }

//    func testNSLoadTestsProfiling() {
//        measureBlock { self.testNSLoadLibxmlTests() }
//    }
//
//    func testNSLoadLibxmlTests() {
//        // some files crash NSXMLParser!
//        let skip = ["xmltutorial.xml", "badcomment.xml", "defattr2.xml", "example-8.xml", "xmlbase-c14n11spec-102.xml", "xmlbase-c14n11spec2-102.xml"]
//
//        enumerateLibXMLTests { file in
//            if contains(skip, file.lastPathComponent) {
//                return
//            }
//            var error: NSError?
//            println("parsing: \(file)")
//            let doc = NSXMLDocument(contentsOfURL: NSURL(fileURLWithPath: file)!, options: 0, error: &error)
//            let nodes = doc?.nodesForXPath("//*", error: &error)
//            if let nodes = nodes {
//                XCTAssert(nodes.count > 0)
//            }
//        }
//    }
}


/// assign the given field to the given variable, just like "=" except that the assignation is returned by the function: “Unlike the assignment operator in C and Objective-C, the assignment operator in Swift does not itself return a value”
private func <- <T>(inout assignee: T?, assignation: T) -> T {
    assignee = assignation
    return assignation
}
infix operator <- { assignment }


