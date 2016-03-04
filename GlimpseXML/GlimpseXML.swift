//
//  GlimpseXML.swift
//  GlimpseXML
//
//  Created by Marc Prud'hommeaux on 10/13/14.
//  Copyright (c) 2014 glimpse.io. All rights reserved.
//

import libxml2

private typealias DocumentPtr = UnsafePointer<xmlDoc>
private typealias NodePtr = UnsafePointer<xmlNode>
private typealias NamespacePtr = UnsafePointer<xmlNs>

private func castDoc(doc: DocumentPtr)->xmlDocPtr { return UnsafeMutablePointer<xmlDoc>(doc) }
private func castNode(node: NodePtr)->xmlNodePtr { return UnsafeMutablePointer<xmlNode>(node) }
private func castNs(ns: NamespacePtr)->xmlNsPtr { return UnsafeMutablePointer<xmlNs>(ns) }


/// The root of an XML Document, containing a single root element
public final class Document: Equatable, Hashable, CustomDebugStringConvertible {
    private let docPtr: DocumentPtr
    private var ownsDoc: Bool


    /// Creates a new Document with the given version string and root node
    public init(version: String? = nil, root: Node? = nil) {
        xmlInitParser()
        precondition(xmlHasFeature(XML_WITH_THREAD) != 0)
        xmlSetStructuredErrorFunc(nil) { ctx, err in } // squelch errors going to stdout
        defer { xmlSetStructuredErrorFunc(nil, nil) }

        self.ownsDoc = true
        self.docPtr = version != nil ? DocumentPtr(xmlNewDoc(version!)) : DocumentPtr(xmlNewDoc(nil))

        if let root = root {
            root.detach()
            xmlDocSetRootElement(castDoc(self.docPtr), castNode(root.nodePtr))
            root.ownsNode = false // ownership transfers to document
        }
    }

    /// Create a new Document by performing a deep copy of the doc parameter
    public required convenience init(copy: Document) {
        self.init(doc: DocumentPtr(xmlCopyDoc(castDoc(copy.docPtr), 1 /* 1 => recursive */)), owns: true)
    }

    private init(doc: DocumentPtr, owns: Bool) {
        self.ownsDoc = owns
        self.docPtr = doc
    }

    deinit {
        if ownsDoc {
            xmlFreeDoc(castDoc(docPtr))
        }
    }

    public var hashValue: Int { return 0 }

    /// Create a curried xpath finder with the given namespaces
    public func xpath(ns: [String:String]? = nil)(_ path: String) throws -> [Node] {
        return try rootElement.xpath(path, namespaces: ns)
    }

    public func xpath(path: String, namespaces: [String:String]? = nil) throws -> [Node] {
        return try rootElement.xpath(path, namespaces: namespaces)
    }

    public func serialize(indent indent: Bool = false, encoding: String? = "utf8") -> String {
        var buf: UnsafeMutablePointer<xmlChar> = nil
        var buflen: Int32 = 0
        let format: Int32 = indent ? 1 : 0

        if let encoding = encoding {
            xmlDocDumpFormatMemoryEnc(castDoc(self.docPtr), &buf, &buflen, encoding, format)
        } else {
            xmlDocDumpFormatMemory(castDoc(self.docPtr), &buf, &buflen, format)
        }

        var string: String = ""
        if buflen >= 0 {
            if let str = stringFromFixedCString(UnsafeBufferPointer(start: UnsafePointer(buf), count: Int(buflen))) {
                string = str
            }
            buf.dealloc(Int(buflen))
        }

        return string
    }

    public var debugDescription: String { return serialize() ?? "<XMLDocument>" }

    public var rootElement: Node {
        get { return Node(node: NodePtr(xmlDocGetRootElement(castDoc(docPtr))), owns: false) }
    }

    /// Parses the XML contained in the given string, returning the Document or an Error
    public class func parseString(xmlString: String, encoding: String? = nil, html: Bool = false) throws -> Document {
        var doc: Document?
        var err: ErrorType?
        // FIXME: withCString doesn't declare rethrows, so we need to hold value & error in bogus optionals
        let _: Void = xmlString.withCString { str in
            do {
                doc = try self.parseData(str, length: Int(strlen(str)), html: html)
            } catch {
                err = error
            }
        }
        if let err = err { throw err }
        return doc!
    }

    /// Parses the XML contained in the given data, returning the Document or an Error
    public class func parseData(xmlData: UnsafePointer<CChar>, length: Int, encoding: String? = nil, html: Bool = false) throws -> Document {
        return try parse(.Data(data: xmlData, length: Int32(length)), encoding: encoding, html: html)
    }

    /// Parses the XML contained at the given filename, returning the Document or an Error
    public class func parseFile(fileName: String, encoding: String? = nil, html: Bool = false) throws -> Document {
        return try parse(.File(fileName: fileName), encoding: encoding, html: html)
    }

    /// The source of the loading for the XML data
    enum XMLLoadSource {
        case File(fileName: String)
        case Data(data: UnsafePointer<CChar>, length: Int32)
    }

    private class func parse(source: XMLLoadSource, encoding: String?, html: Bool) throws -> Document {
        xmlInitParser()
        precondition(xmlHasFeature(XML_WITH_THREAD) != 0)
        xmlSetStructuredErrorFunc(nil) { ctx, err in } // squelch errors going to stdout
        defer { xmlSetStructuredErrorFunc(nil, nil) }

        let opts : Int32 = Int32(XML_PARSE_NONET.rawValue)

        if html {
            precondition(xmlHasFeature(XML_WITH_HTML) != 0)
        }

        let ctx = html ? htmlNewParserCtxt() : xmlNewParserCtxt()
        defer {
            if html {
                htmlFreeParserCtxt(ctx)
            } else {
                xmlFreeParserCtxt(ctx)
            }
        }

        var doc: xmlDocPtr? // also htmlDocPtr: “Most of the back-end structures from XML and HTML are shared.”

        switch (html, source) {
        case (false, .File(let fileName)):
            if let encoding = encoding {
                doc = xmlCtxtReadFile(ctx, fileName, encoding, opts)
            } else {
                doc = xmlCtxtReadFile(ctx, fileName, nil, opts)
            }
        case (false, .Data(let data, let length)):
            if let encoding = encoding {
                doc = xmlCtxtReadMemory(ctx, data, length, nil, encoding, opts)
            } else {
                doc = xmlCtxtReadMemory(ctx, data, length, nil, nil, opts)
            }
        case (true, .File(let fileName)):
            if let encoding = encoding {
                doc = htmlCtxtReadFile(ctx, fileName, encoding, opts)
            } else {
                doc = htmlCtxtReadFile(ctx, fileName, nil, opts)
            }
        case (true, .Data(let data, let length)):
            if let encoding = encoding {
                doc = htmlCtxtReadMemory(ctx, data, length, nil, encoding, opts)
            } else {
                doc = htmlCtxtReadMemory(ctx, data, length, nil, nil, opts)
            }
        }

        let err = errorFromXmlError(ctx.memory.lastError)

        if let doc = doc {
            if doc != nil { // unwrapped pointer can still be nil
                let document = Document(doc: DocumentPtr(doc), owns: true)
                return document
            }
        }

        throw err
    }

}

/// Equality is defined by whether the underlying document pointer is the same
public func ==(lhs: Document, rhs: Document) -> Bool {
    return castDoc(lhs.docPtr) == castDoc(rhs.docPtr)
}


/// A Node in an Document
public final class Node: Equatable, Hashable, CustomDebugStringConvertible {
    private let nodePtr: NodePtr
    private var ownsNode: Bool

    private init(node: NodePtr, owns: Bool) {
        self.ownsNode = owns
        self.nodePtr = node
    }

    public init(doc: Document? = nil, cdata: String) {
        self.ownsNode = doc == nil
        self.nodePtr = NodePtr(xmlNewCDataBlock(doc == nil ? nil : castDoc(doc!.docPtr), cdata, Int32(cdata.nulTerminatedUTF8.count)))
    }

    public init(doc: Document? = nil, text: String) {
        self.ownsNode = doc == nil
        self.nodePtr = NodePtr(xmlNewText(text))
    }

    public init(doc: Document? = nil, name: String? = nil, namespace: Namespace? = nil, attributes: [(name: String, value: String)]? = nil, text: String? = nil, children: [Node]? = nil) {
        self.ownsNode = doc == nil


        self.nodePtr = NodePtr(xmlNewDocNode(doc == nil ? nil : castDoc(doc!.docPtr), namespace == nil ? nil : castNs(namespace!.nsPtr), name ?? "", text ?? ""))

        let _ = attributes?.map { self.updateAttribute($0, value: $1, namespace: namespace) }

        if let children = children {
            self.children = children
        }
    }

    public required convenience init(copy: Node) {
        self.init(node: NodePtr(xmlCopyNode(castNode(copy.nodePtr), 1 /* 1 => recursive */)), owns: true)
    }

    deinit {
        if ownsNode {
            xmlFreeNode(castNode(nodePtr))
        }
    }

    public var hashValue: Int { return name?.hashValue ?? 0 }

    /// Returns a deep copy of the current node
    public func copy() -> Node {
        return Node(copy: self)
    }

    /// The name of the node
    public var name: String? {
        get { return stringFromXMLString(castNode(nodePtr).memory.name) }
        set(value) {
            if let value = value {
                xmlNodeSetName(castNode(nodePtr), value)
            } else {
                xmlNodeSetName(castNode(nodePtr), nil)
            }
        }
    }

    /// The text content of the node
    public var text: String? {
        get { return stringFromXMLString(xmlNodeGetContent(castNode(nodePtr)), free: true) }

        set(value) {
            if let value = value {
                xmlNodeSetContent(castNode(nodePtr), value)
            } else {
                xmlNodeSetContent(castNode(nodePtr), nil)
            }
        }
    }

    /// The parent node of the node
    public var parent: Node? {
        let parentPtr = castNode(nodePtr).memory.parent
        if parentPtr == nil {
            return nil
        } else {
            return Node(node: NodePtr(parentPtr), owns: false)
        }
    }

    /// The next sibling of the node
    public var next: Node? {
        get {
            let nextPtr = castNode(nodePtr).memory.next
            if nextPtr == nil {
                return nil
            } else {
                return Node(node: NodePtr(nextPtr), owns: false)
            }
        }

        set(node) {
            if let node = node {
                node.detach()
                xmlAddNextSibling(castNode(nodePtr), castNode(node.nodePtr))
                node.ownsNode = false
            }
        }
    }

    /// The previous sibling of the node
    public var prev: Node? {
        get {
            let prevPtr = castNode(nodePtr).memory.prev
            if prevPtr == nil {
                return nil
            } else {
                return Node(node: NodePtr(prevPtr), owns: false)
            }
        }

        set(node) {
            if let node = node {
                node.detach()
                xmlAddPrevSibling(castNode(nodePtr), castNode(node.nodePtr))
                node.ownsNode = false
            }
        }

    }

    /// The child nodes of the current node
    public var children: [Node] {
        get {
            var nodes = [Node]()
            for var child = castNode(nodePtr).memory.children; child != nil; child = child.memory.next {
                nodes += [Node(node: NodePtr(child), owns: false)]
            }
            return nodes
        }

        set(newChildren) {
            children.map { $0.detach() } // remove existing children from parent
            newChildren.map { self.addChild($0) }
        }
    }

    /// Adds the given node to the end of the child node list; if the child is already in a node tree then a copy will be added and the copy will be returned
    public func addChild(child: Node) -> Node {
        if child.ownsNode {
            // we don't have enough information to transfer ownership directly, do copy instead?
            child.ownsNode = false // ownership transfers to the new parent
            xmlAddChild(castNode(nodePtr), castNode(child.nodePtr))
            return child
        } else {
            let childCopy = Node(copy: child)
            xmlAddChild(castNode(nodePtr), castNode(childCopy.nodePtr))
            return childCopy
        }
    }

    /// Removes the node from a parent
    public func detach() {
        xmlUnlinkNode(castNode(nodePtr))
        self.ownsNode = true // ownership goes to self
    }

    /// Returns the value for the given attribute name with the optional namespace
    public func attributeValue(name: String, namespace: Namespace? = nil) -> String? {
        if let href = namespace?.href {
            return stringFromXMLString(xmlGetNsProp(castNode(nodePtr), name, href))
        } else {
            return stringFromXMLString(xmlGetNoNsProp(castNode(nodePtr), name))
        }
    }

    /// Updates the value for the given attribute
    public func updateAttribute(name: String, value: String, namespace: Namespace? = nil) {
        if let namespace = namespace {
            xmlSetNsProp(castNode(nodePtr), castNs(namespace.nsPtr), name, value)
        } else {
            xmlSetProp(castNode(nodePtr), name, value)
        }
    }

    /// Removes the given attribute
    public func removeAttribute(name: String, namespace: Namespace? = nil) -> Bool {
        var attr: xmlAttrPtr
        if let href = namespace?.href {
            attr = xmlHasNsProp(castNode(nodePtr), name, href)
        } else {
            attr = xmlHasProp(castNode(nodePtr), name)
        }

        if attr != nil {
            xmlRemoveProp(attr)
            return true
        } else {
            return false
        }
    }

    /// Node subscripts get and set namespace-less attributes on the element
    public subscript(attribute: String) -> String? {
        get {
            return attributeValue(attribute)
        }

        set(value) {
            if let value = value {
                updateAttribute(attribute, value: value)
            } else {
                removeAttribute(attribute)
            }
        }
    }

    /// The name of the type of node
    public var nodeType: String {
        switch castNode(nodePtr).memory.type.rawValue {
        case XML_ELEMENT_NODE.rawValue: return "Element"
        case XML_ATTRIBUTE_NODE.rawValue: return "Attribute"
        case XML_TEXT_NODE.rawValue: return "Text"
        case XML_CDATA_SECTION_NODE.rawValue: return "CDATA"
        case XML_ENTITY_REF_NODE.rawValue: return "EntityRef"
        case XML_ENTITY_NODE.rawValue: return "Entity"
        case XML_PI_NODE.rawValue: return "PI"
        case XML_COMMENT_NODE.rawValue: return "Comment"
        case XML_DOCUMENT_NODE.rawValue: return "Document"
        case XML_DOCUMENT_TYPE_NODE.rawValue: return "DocumentType"
        case XML_DOCUMENT_FRAG_NODE.rawValue: return "DocumentFrag"
        case XML_NOTATION_NODE.rawValue: return "Notation"
        case XML_HTML_DOCUMENT_NODE.rawValue: return "HTMLDocument"
        case XML_DTD_NODE.rawValue: return "DTD"
        case XML_ELEMENT_DECL.rawValue: return "ElementDecl"
        case XML_ATTRIBUTE_DECL.rawValue: return "AttributeDecl"
        case XML_ENTITY_DECL.rawValue: return "EntityDecl"
        case XML_NAMESPACE_DECL.rawValue: return "NamespaceDecl"
        case XML_XINCLUDE_START.rawValue: return "XIncludeStart"
        case XML_XINCLUDE_END.rawValue: return "XIncludeEnd"
        case XML_DOCB_DOCUMENT_NODE.rawValue: return "Document"
        default: return "Unknown"
        }
    }

    /// Returns this node as an XML string with optional indentation
    public func serialize(indent indent: Bool = false) -> String {
        let buf = xmlBufferCreate()

        let level: Int32 = 0
        let format: Int32 = indent ? 1 : 0

        let result = xmlNodeDump(buf, castNode(nodePtr).memory.doc, castNode(nodePtr), level, format)

        var string: String = ""
        if result >= 0 {
            let buflen: Int32 = xmlBufferLength(buf)
            let str: UnsafePointer<CUnsignedChar> = xmlBufferContent(buf)
            if let str = stringFromFixedCString(UnsafeBufferPointer(start: UnsafePointer(str), count: Int(buflen))) {
                string = str
            }
        }

        xmlBufferFree(buf)
        return string
    }

    /// The owning document for the node, if any
    public var document: Document? {
        let docPtr = castNode(nodePtr).memory.doc
        return docPtr == nil ? nil : Document(doc: DocumentPtr(docPtr), owns: false)
    }

    public var debugDescription: String {
        return "[\(nodeType)]: \(serialize())"
    }

    /// Evaluates the given xpath and returns matching nodes
    public func xpath(path: String, namespaces: [String:String]? = nil) throws -> [Node] {

        // xmlXPathNewContext requires that a node be part of a document; host it inside a temporary one if it is standalone
        var nodeDoc = castNode(nodePtr).memory.doc
        if nodeDoc == nil {
            nodeDoc = xmlNewDoc(nil)
            var topParent = castNode(nodePtr)
            while topParent.memory.parent != nil {
                topParent = topParent.memory.parent
            }
            xmlDocSetRootElement(nodeDoc, topParent)

            // release our temporary document when we are done
            defer {
                xmlUnlinkNode(topParent)
                xmlSetTreeDoc(topParent, nil)
                xmlFreeDoc(nodeDoc)
            }
        }

        let xpathCtx = xmlXPathNewContext(nodeDoc)
        defer { xmlXPathFreeContext(xpathCtx) }

        if xpathCtx == nil {
            throw XMLError(message: "Could not create XPath context")
        }

        if let namespaces = namespaces {
            for (prefix, uri) in namespaces {
                xmlXPathRegisterNs(xpathCtx, prefix, uri)
            }
        }

        let xpathObj = xmlXPathNodeEval(castNode(nodePtr), path, xpathCtx)
        if xpathObj == nil {
            let lastError = xpathCtx.memory.lastError
            let error = errorFromXmlError(lastError)
            throw error
        }
        defer { xmlXPathFreeObject(xpathObj) }

        var results = [Node]()
        let nodeSet = xpathObj.memory.nodesetval
        if nodeSet != nil {
            for var index = 0, count = Int(nodeSet.memory.nodeNr); index < count; index++ {
                let node = nodeSet.memory.nodeTab[index]
                if node != nil {
                    results += [Node(node: NodePtr(node), owns: false)]
                }
            }
        }
        return results
    }
}


/// Equality is defined by whether the underlying node pointer is identical
public func ==(lhs: Node, rhs: Node) -> Bool {
    return castNode(lhs.nodePtr) == castNode(rhs.nodePtr)
}

/// Appends the right node as a child of the left node
public func +=(lhs: Node, rhs: Node) -> Node {
    lhs.addChild(rhs)
    return rhs
}


private func errorFromXmlError(error: xmlError)->XMLError {
    let level = errorLevelFromXmlErrorLevel(error.level)
    return XMLError(domain: XMLError.ErrorDomain.fromErrorDomain(error.domain), code: error.code, message: String.fromCString(error.message) ?? "", level: level, file: String.fromCString(error.file) ?? "", line: error.line, str1: String.fromCString(error.str1) ?? "", str2: String.fromCString(error.str2) ?? "", str3: String.fromCString(error.str3) ?? "", int1: error.int1, column: error.int2)
}

private func errorLevelFromXmlErrorLevel(level: xmlErrorLevel) -> XMLError.ErrorLevel {
    switch level.rawValue {
    case XML_ERR_NONE.rawValue: return .None
    case XML_ERR_WARNING.rawValue: return .Warning
    case XML_ERR_ERROR.rawValue: return .Error
    case XML_ERR_FATAL.rawValue: return .Fatal
    default: return .None
    }
}

/// A namespace for a document, node, or attribute
public class Namespace {
    private let nsPtr: NamespacePtr
    private let ownsNode: Bool

    private init(ns: NamespacePtr, owns: Bool) {
        self.ownsNode = owns
        self.nsPtr = ns
    }

    public init(href: String, prefix: String, node: Node? = nil) {
        self.ownsNode = node == nil
        self.nsPtr = NamespacePtr(xmlNewNs(node == nil ? nil : castNode(node!.nodePtr), href, prefix))
    }

    public required convenience init(copy: Namespace) {
        self.init(ns: NamespacePtr(xmlCopyNamespace(castNs(copy.nsPtr))), owns: true)
    }

    deinit {
        if ownsNode {
            xmlFreeNs(castNs(nsPtr))
        }
    }

    private var href: String? { return stringFromXMLString(castNs(nsPtr).memory.href) }
    private var prefix: String? { return stringFromXMLString(castNs(nsPtr).memory.prefix) }
    
}


/// MARK: General Utilities

/// The result of an XML operation, which may be a T or an Error condition
public enum XMLResult<T>: CustomDebugStringConvertible {
    case Value(XMLValue<T>)
    case Error(XMLError)

    public var debugDescription: String {
        switch self {
        case .Value(let v): return "value: \(v)"
        case .Error(let e): return "error: \(e)"
        }
    }

    public var value: T? {
        switch self {
        case .Value(let v): return v.value
        case .Error: return nil
        }
    }

    public var error: XMLError? {
        switch self {
        case .Value: return nil
        case .Error(let e): return e
        }
    }

}

/// Wrapper for a generic value; workaround for Swift enum generic deficiency
public class XMLValue<T> {
    public let value: T
    public init(_ value: T) { self.value = value }
}

// A stuctured XML parse of processing error
public struct XMLError: CustomDebugStringConvertible {

    public enum ErrorLevel: CustomDebugStringConvertible {
        case None, Warning, Error, Fatal

        public var debugDescription: String {
            switch self {
            case None: return "None"
            case Warning: return "Warning"
            case Error: return "Error"
            case Fatal: return "Fatal"
            }
        }
    }

    /// The domain (type) of error that occurred
    public enum ErrorDomain: UInt, CustomDebugStringConvertible {
        case None, Parser, Tree, Namespace, DTD, HTML, Memory, Output, IO, FTP, HTTP, XInclude, XPath, XPointer, Regexp, Datatype, SchemasP, SchemasV, RelaxNGP, RelaxNGV, Catalog, C14N, XSLT, Valid, Check, Writer, Module, I18N, SchematronV, Buffer, URI

        public var debugDescription: String {
            switch self {
            case None: return "None"
            case Parser: return "Parser"
            case Tree: return "Tree"
            case Namespace: return "Namespace"
            case DTD: return "DTD"
            case HTML: return "HTML"
            case Memory: return "Memory"
            case Output: return "Output"
            case IO: return "IO"
            case FTP: return "FTP"
            case HTTP: return "HTTP"
            case XInclude: return "XInclude"
            case XPath: return "XPath"
            case XPointer: return "XPointer"
            case Regexp: return "Regexp"
            case Datatype: return "Datatype"
            case SchemasP: return "SchemasP"
            case SchemasV: return "SchemasV"
            case RelaxNGP: return "RelaxNGP"
            case RelaxNGV: return "RelaxNGV"
            case Catalog: return "Catalog"
            case C14N: return "C14N"
            case XSLT: return "XSLT"
            case Valid: return "Valid"
            case Check: return "Check"
            case Writer: return "Writer"
            case Module: return "Module"
            case I18N: return "I18N"
            case SchematronV: return "SchematronV"
            case Buffer: return "Buffer"
            case URI: return "URI"
            }
        }

        public static func fromErrorDomain(domain: Int32) -> ErrorDomain {
            return ErrorDomain(rawValue: UInt(domain)) ?? .None
        }
    }

    /// What part of the library raised this error
    public let domain: ErrorDomain

    /// The error code.level: return XXX
    public let code: Int32

    /// human-readable informative error message
    public let message: String

    /// how consequent is the error
    public let level: ErrorLevel

    /// the filename
    public let file: String

    /// the line number if available
    public let line: Int32

    /// column number of the error or 0 if N/A
    public let column: Int32

    /// extra string information
    public let str1: String

    /// extra string information
    public let str2: String

    /// extra string information
    public let str3: String

    /// extra number information
    public let int1: Int32

    public init(domain: ErrorDomain, code: Int32, message: String, level: ErrorLevel, file: String, line: Int32, str1: String, str2: String, str3: String, int1: Int32, column: Int32) {
        self.domain = domain
        self.code = code
        self.message = message
        self.level = level
        self.file = file
        self.line = line
        self.str1 = str1
        self.str2 = str2
        self.str3 = str3
        self.int1 = int1
        self.column = column
    }

    public init(message: String) {
        self.init(domain: ErrorDomain.None, code: 0, message: message, level: ErrorLevel.Fatal, file: "", line: 0, str1: "", str2: "", str3: "", int1: 0, column: 0)
    }

    public var debugDescription: String {
        return "\(domain) \(level) [\(line):\(column)]: \(message)"
    }
}

extension XMLError: ErrorType {
    // FIXME: needed for ErrorType conformance in Swift 2 beta
    public var _domain: String { return domain.debugDescription }
    public var _code: Int { return Int(code) }
}

private func stringFromXMLString(string: UnsafePointer<xmlChar>, free: Bool = false) -> String? {
    let str = String.fromCString(UnsafePointer(string))
    if free {
        xmlFree(UnsafeMutablePointer<Void>(string))
    }
    return str
}

private func stringFromFixedCString(cs: UnsafeBufferPointer<CChar>) -> String? {
    let buf = UnsafeMutablePointer<CChar>.alloc(cs.count + 1)
    buf.initializeFrom(cs + [0]) // tack on a zero to make it a valid c string
    let (s, _) = String.fromCStringRepairingIllFormedUTF8(buf)
    buf.dealloc(cs.count + 1)
    return s
}
