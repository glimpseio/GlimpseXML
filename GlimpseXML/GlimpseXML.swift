//
//  GlimpseXML.swift
//  GlimpseXML
//
//  Created by Marc Prud'hommeaux on 10/13/14.
//  Copyright (c) 2014 glimpse.io. All rights reserved.
//


/*
    These Void typealiases exist becuase if an external module references the GlimpseXML module when any of the classes reference any of the xml* structs in any way (function returns, private properties, etc), then the compiler will crash unless those modules themselves import the $(SDKROOT)/usr/include/libxml2 headers (which we don't want to require). So while the first commented-out typealiases will allow the GlimpseXML module to build, no other module can reference it.
*/

//private typealias DocumentPtr = UnsafePointer<xmlDoc>
//private typealias NodePtr = UnsafePointer<xmlNode>
//private typealias NamespacePtr = UnsafePointer<xmlNs>

private typealias DocumentPtr = UnsafePointer<Void>
private typealias NodePtr = UnsafePointer<Void>
private typealias NamespacePtr = UnsafePointer<Void>


private func castDoc(doc: DocumentPtr)->xmlDocPtr { return UnsafeMutablePointer<xmlDoc>(doc) }
private func castNode(node: NodePtr)->xmlNodePtr { return UnsafeMutablePointer<xmlNode>(node) }
private func castNs(ns: NamespacePtr)->xmlNsPtr { return UnsafeMutablePointer<xmlNs>(ns) }


private var parserinit: Void = xmlInitParser() // lazy var that needs to be called to initialize libxml threads

/// The root of an XML Document, containing a single root element
public final class Document: Equatable, Hashable, DebugPrintable {
    private let docPtr: DocumentPtr
    private var ownsDoc: Bool


    /// Creates a new Document with the given version string and root node
    public init(version: String? = nil, root: Node? = nil) {
        let pinit: Void = parserinit // ensure lazy var is invoked
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
        let pinit: Void = parserinit // ensure lazy var is invoked
        self.ownsDoc = owns
        self.docPtr = doc
    }

    deinit {
        if ownsDoc {
            xmlFreeDoc(castDoc(docPtr))
        }
    }

    public var hashValue: Int { return 0 }

    public func xpath(path: String, namespaces: [String:String]? = nil) -> XMLResult<[Node]> {
        return rootElement.xpath(path, namespaces: namespaces)
    }

    public func serialize(indent: Bool = false, encoding: String? = "utf8") -> String {
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
            let cchars: UnsafePointer<CChar> = UnsafePointer(buf)
            if let str = stringFromFixedCString(cchars, Int(buflen)) {
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
    public class func parseString(xmlString: String, encoding: String? = nil) -> XMLResult<Document> {
        return xmlString.withCString { self.parseData($0, length: Int(strlen($0))) }
    }

    /// Parses the XML contained in the given data, returning the Document or an Error
    public class func parseData(xmlData: UnsafePointer<CChar>, length: Int, encoding: String? = nil) -> XMLResult<Document> {
        return parse(XMLLoadSource.Data(data: xmlData, length: Int32(length)), encoding: encoding)
    }

    /// Parses the XML contained at the given filename, returning the Document or an Error
    public class func parseFile(fileName: String, encoding: String? = nil) -> XMLResult<Document> {
        return parse(.File(fileName: fileName), encoding: encoding)
    }

    /// The source of the loading for the XML data
    enum XMLLoadSource {
        case File(fileName: String)
        case Data(data: UnsafePointer<CChar>, length: Int32)
    }

    private class func parse(source: XMLLoadSource, encoding: String?, stderr: Bool = false) -> XMLResult<Document> {
        let pinit: Void = parserinit // ensure lazy var is invoked
        precondition(xmlHasFeature(XML_WITH_THREAD) != 0)

        // var x: xmlParserOption = XML_PARSE_NOCDATA
        var opts : Int32 = 0

        let ctx = xmlNewParserCtxt()
        var doc: xmlDocPtr?

        if !stderr {
            GlimpseXMLGenericErrorCallbackCreate(nil) // squelch errors from going to stderr
        }

        switch source {
        case .File(let fileName):
            if let encoding = encoding {
                doc = xmlCtxtReadFile(ctx, fileName, encoding, Int32(opts))
            } else {
                doc = xmlCtxtReadFile(ctx, fileName, nil, Int32(opts))
            }
        case .Data(let data, let length):
            if let encoding = encoding {
                doc = xmlCtxtReadMemory(ctx, data, length, nil, encoding, Int32(opts))
            } else {
                doc = xmlCtxtReadMemory(ctx, data, length, nil, nil, Int32(opts))
            }
        }

        if !stderr {
            GlimpseXMLGenericErrorCallbackDestroy() // clear the error handler
        }

        let err = errorFromXmlError(ctx.memory.lastError)
        xmlFreeParserCtxt(ctx);

        if let doc = doc {
            if doc != nil { // unwrapped pointer can still be nil
                let document = Document(doc: DocumentPtr(doc), owns: true)
                return .Value(XMLValue(document))
            }
        }

        return .Error(err)
    }

}

/// Equality is defined by whether the underlying document pointer is the same
public func ==(lhs: Document, rhs: Document) -> Bool {
    return castDoc(lhs.docPtr) == castDoc(rhs.docPtr)
}


/// A Node in an Document
public final class Node: Equatable, Hashable, DebugPrintable {
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

        attributes?.map { self.updateAttribute($0, value: $1, namespace: namespace) }

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
        get { return stringFromXMLString(xmlNodeGetContent(castNode(nodePtr))) }
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
        switch castNode(nodePtr).memory.type.value {
        case XML_ELEMENT_NODE.value: return "Element"
        case XML_ATTRIBUTE_NODE.value: return "Attribute"
        case XML_TEXT_NODE.value: return "Text"
        case XML_CDATA_SECTION_NODE.value: return "CDATA"
        case XML_ENTITY_REF_NODE.value: return "EntityRef"
        case XML_ENTITY_NODE.value: return "Entity"
        case XML_PI_NODE.value: return "PI"
        case XML_COMMENT_NODE.value: return "Comment"
        case XML_DOCUMENT_NODE.value: return "Document"
        case XML_DOCUMENT_TYPE_NODE.value: return "DocumentType"
        case XML_DOCUMENT_FRAG_NODE.value: return "DocumentFrag"
        case XML_NOTATION_NODE.value: return "Notation"
        case XML_HTML_DOCUMENT_NODE.value: return "HTMLDocument"
        case XML_DTD_NODE.value: return "DTD"
        case XML_ELEMENT_DECL.value: return "ElementDecl"
        case XML_ATTRIBUTE_DECL.value: return "AttributeDecl"
        case XML_ENTITY_DECL.value: return "EntityDecl"
        case XML_NAMESPACE_DECL.value: return "NamespaceDecl"
        case XML_XINCLUDE_START.value: return "XIncludeStart"
        case XML_XINCLUDE_END.value: return "XIncludeEnd"
        case XML_DOCB_DOCUMENT_NODE.value: return "Document"
        default: return "Unknown"
        }
    }

    /// Returns this node as an XML string with optional indentation
    public func serialize(indent: Bool = false) -> String {
        let buf = xmlBufferCreate()

        let level: Int32 = 0
        let format: Int32 = indent ? 1 : 0

        let result = xmlNodeDump(buf, castNode(nodePtr).memory.doc, castNode(nodePtr), level, format)

        var string: String = ""
        if result >= 0 {
            let buflen: Int32 = xmlBufferLength(buf)
            let str: UnsafePointer<CUnsignedChar> = xmlBufferContent(buf)
            let cchars: UnsafePointer<CChar> = UnsafePointer(str)
            if let str = stringFromFixedCString(cchars, Int(buflen)) {
                string = str
            }
        }

        xmlBufferFree(buf)
        return string
    }

    /// The owning document for the node, if any
    public var document: Document? {
        var docPtr = castNode(nodePtr).memory.doc
        return docPtr == nil ? nil : Document(doc: DocumentPtr(docPtr), owns: false)
    }

    public var debugDescription: String {
        return "[\(nodeType)]: \(serialize())"
    }

    /// Evaluates the given xpath and returns matching nodes
    public func xpath(path: String, namespaces: [String:String]? = nil) -> XMLResult<[Node]> {

        GlimpseXMLGenericErrorCallbackCreate(nil) // squelch errors from going to stderr
        var cleanup: (XMLResult<[Node]>)->XMLResult<[Node]> = {
            GlimpseXMLGenericErrorCallbackDestroy() // clear the error handler
            return $0
        }

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
            cleanup = {
                xmlUnlinkNode(topParent)
                xmlSetTreeDoc(topParent, nil)
                xmlFreeDoc(nodeDoc)
                GlimpseXMLGenericErrorCallbackDestroy()
                return $0
            }
        }

        let xpathCtx = xmlXPathNewContext(nodeDoc)

        if xpathCtx != nil {
            if let namespaces = namespaces {
                for (prefix, uri) in namespaces {
                    xmlXPathRegisterNs(xpathCtx, prefix, uri)
                }
            }

            let xpathObj = xmlXPathNodeEval(castNode(nodePtr), path, xpathCtx)
            if xpathObj != nil {
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
                xmlXPathFreeObject(xpathObj)
                xmlXPathFreeContext(xpathCtx)
                return cleanup(.Value(XMLValue(results)))
            } else {
                let lastError = xpathCtx.memory.lastError
                let error = errorFromXmlError(lastError)
                xmlXPathFreeContext(xpathCtx)
                return cleanup(.Error(error))
            }
        }

        return cleanup(.Error(XMLError(message: "Unknown XPath error")))
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
    switch level.value {
    case XML_ERR_NONE.value: return .None
    case XML_ERR_WARNING.value: return .Warning
    case XML_ERR_ERROR.value: return .Error
    case XML_ERR_FATAL.value: return .Fatal
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
public enum XMLResult<T>: DebugPrintable {
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
        case .Error(let e): return nil
        }
    }

    public var error: XMLError? {
        switch self {
        case .Value(let v): return nil
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
public struct XMLError: DebugPrintable {
    public enum ErrorLevel: DebugPrintable {
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
    public enum ErrorDomain: UInt, DebugPrintable {
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


private func stringFromXMLString(string: UnsafePointer<xmlChar>) -> String? {
    return String.fromCString(UnsafePointer(string))
}

private func stringFromFixedCString(cs: UnsafePointer<CChar>, length: Int) -> String? {
    // taken from <http://stackoverflow.com/questions/25042695/swift-converting-from-unsafepointeruint8-with-length-to-string>
    let buflen = length + 1
    var buf = UnsafeMutablePointer<CChar>.alloc(buflen)
    memcpy(buf, cs, length)
    buf[length] = 0 // zero terminate
    let s = String.fromCString(buf)
    buf.dealloc(buflen)
    return s
}
