import Foundation
import CommandLineKit


/*
 TODO:
 1. handle Css Rules (in event that the static easylist has css rules)
 2. handle "generichide" && "elemhide" (in event that the static easylist has css rules)
 3. handle "genericblock" (Needs for research. And is it really needed?) & "document"
 4. Merge matching rules in two ways: (This is to reduce the number of rules. The abp2blocklist reduces by 500-600. Not very important though.) OPTIONAL.
    a. Rules with same action and other trigger properties except url-filter (merge url-filter)
    b. Merge if-domains of rules with same action and other properties.
 5. Test as much as possible.
 */


protocol JSONRepresentable {
    func jsonify()-> String
}

class Rule: Hashable, JSONRepresentable {
    var trigger: Trigger!
    var action: Action!
    var ruleID: RuleIdentifier
    
    func jsonify() -> String {
        return "{\(trigger.jsonify()), \(action.jsonify())}"
    }
    
    static func == (lhs: Rule, rhs: Rule) -> Bool {
        return lhs.trigger == rhs.trigger && lhs.action == rhs.action
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(trigger)
        hasher.combine(action)
    }
    
    init?(str: String) {
        let isBlockingRule: Bool = !str.hasPrefix("@@")
        var mutableStr = str
        !isBlockingRule ? mutableStr.removeFirst(2) : nil
        
        // let's build trigger
        if let trigger = Trigger(str: mutableStr) {
            self.trigger = trigger
            action = trigger.createAction(isBlockingRule: isBlockingRule)
            ruleID = RuleIdentifier(trigger: trigger, action: action)
        } else {
            return nil
        }
    }
}

enum EasyListOptions: String {
    case font = "font"
    case media = "media"
    case script = "script"
    case stylesheet = "stylesheet"
    case object = "object"
    case image = "image"
    case xmlhttprequest = "xmlhttprequest"
    case objectSubrequest = "object-subrequest"
    case subdocument = "subdocument"
    case ping = "ping"
    case websocket = "websocket"
    case webrtc = "webrtc"
    case document = "document"
    case elemhide = "elemhide"
    case generichide = "generichide"
    case genericblock = "genericblock"
    case thirdParty = "third-party"
    case matchcase = "match-case"
    case domain = "domain"
    case popup = "popup"
    case other = "other"
}

enum OptionType: String {
    case domain
    case resource
    case load
    case caseSensitive
    case unknown //GenericHide, GenericBlock, Elemhide
}

enum ResourceTypes: String {
    case document = "document"
    case image = "image"
    case styleSheet = "style-sheet"
    case script = "script"
    case font = "font"
    case raw = "raw"
    case svgDoc = "svg-document"
    case media = "media"
    case popup = "popup"
}

enum LoadTypes: String {
    case firstParty = "first-party"
    case thirdParty = "third-party"
}

enum RegexSpecifiers: String {
    case scheme = "[^:]+:(//)?"
    case domain = "([^/]+\\\\.)?"
    case endSeparator = "([^-_.%a-z0-9].*)?$"
    case separator = "[^-_.%a-z0-9]"
    case wildcard = ".*"
}

enum RegexIdentifiers: String {
    case domain = "^([^:]+:(//)?)?"
}

class RuleIdentifier: Hashable, CustomDebugStringConvertible {
    var debugDescription: String {
        return trigger.urlFilter
    }
    
    var trigger: Trigger
    var action: Action
    static func == (lhs: RuleIdentifier, rhs: RuleIdentifier) -> Bool {
        return lhs.action == rhs.action && lhs.trigger.urlFilterIsCaseSensitive == rhs.trigger.urlFilterIsCaseSensitive &&
                lhs.trigger.ifTopUrl == rhs.trigger.ifTopUrl && lhs.trigger.unlessTopUrl == rhs.trigger.unlessTopUrl &&
                lhs.trigger.ifDomain == rhs.trigger.ifDomain && lhs.trigger.unlessDomain == rhs.trigger.unlessDomain &&
                lhs.trigger.resourceType == rhs.trigger.resourceType && lhs.trigger.loadType == rhs.trigger.loadType
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(action)
        hasher.combine(trigger.ifTopUrl)
        hasher.combine(trigger.unlessTopUrl)
        hasher.combine(trigger.ifDomain)
        hasher.combine(trigger.unlessDomain)
        hasher.combine(trigger.resourceType)
        hasher.combine(trigger.loadType)
        hasher.combine(trigger.urlFilterIsCaseSensitive)
    }
    
    init(trigger: Trigger, action: Action) {
        self.trigger = trigger
        self.action = action
    }
}

extension String {
    func encodeURI() -> String {
        return self.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ";,/?:@&=+$-_.!~*'()#"))) ?? self
    }
    
    func punyCode() -> String {
        return self.utf8HostToAscii()
    }
}

class Trigger: Hashable, JSONRepresentable {
    static func == (lhs: Trigger, rhs: Trigger) -> Bool {
        return lhs.urlFilter == rhs.urlFilter
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(urlFilter)
    }
    
    /* url-filter <REQUIRED>
     A required key-value which specifies a pattern to match the URL against
     */
    var urlFilter: String
    
    /* url-filter-is-case-sensitive
     A Boolean value. The default value is false.
     */
    var urlFilterIsCaseSensitive: Bool?
    
    /* if-domain
     An array of strings matched to a URL's domain; limits action to a list of specific domains. Values must be lowercase ASCII, or punycode for non-ASCII. Add * in front to match domain and subdomains. Can't be used with unless-domain.
     */
    var ifDomain: [String]? {
        didSet{
            ifDomain != nil ? (unlessDomain = nil) : nil
        }
    }
    
    /* unless-domain
     An array of strings matched to a URL's domain; acts on any site except domains in a provided list. Values must be lowercase ASCII, or punycode for non-ASCII. Add * in front to match domain and subdomains. Can't be used with if-domain.
     */
    var unlessDomain: [String]? {
        didSet{
            unlessDomain != nil ? (ifDomain = nil) : nil
        }
    }
    
    /* resource-type
     An array of strings representing the resource types (how the browser intends to use the resource) that the rule should match. If not specified, the rule matches all resource types. Valid values: document, image, style-sheet, script, font, raw (Any untyped load), svg-document, media, popup.
     */
    var resourceType: Set<ResourceTypes>?
    
    /* load-type
     An array of strings that can include one of two mutually exclusive values. If not specified, the rule matches all load types. first-party is triggered only if the resource has the same scheme, domain, and port as the main page resource. third-party is triggered if the resource is not from the same domain as the main page resource.
     */
    var loadType: [LoadTypes]?
    
    /* if-top-url
     An array of strings matched to the entire main document URL; limits the action to a specific list of URL patterns. Values must be lowercase ASCII, or punycode for non-ASCII. Can't be used with unless-top-url.
     
     Currently unused in case of Easylist conversion
     */
    var ifTopUrl: [String]? {
        didSet {
            ifTopUrl != nil ? (unlessTopUrl = nil) : nil
        }
    }
    
    /* unless-top-url
     An array of strings matched to the entire main document URL; acts on any site except URL patterns in provided list. Values must be lowercase ASCII, or punycode for non-ASCII. Can't be used with if-top-url.
     
     Currently unused in case of Easylist conversion
     */
    var unlessTopUrl: [String]? {
        didSet {
            unlessTopUrl != nil ? (ifTopUrl = nil) : nil
        }
    }
    
    // For internal use
    private var scheme: String?
    private var domain: String?
    private var path: String?
    
    private var resources: Set<ResourceTypes> = [.document,
                                                 .script,
                                                 .font,
                                                 .popup,
                                                 .styleSheet,
                                                 .media,
                                                 .raw]
    
    init?(str: String) {
        urlFilter = ""
        if str.range(of: "$") != nil {
            let ruleParts: [String] = str.components(separatedBy: "$")
            if let urlStr = ruleParts.first {
                resolveURLFitler(urlStr: urlStr)
            }
            if let optStr = ruleParts.last {
                do{
                    try resolveOptions(optStr: optStr)
                } catch _ as NSError {
                    return nil
                }
            }
        } else {
            // no options inculded in rule
            resolveURLFitler(urlStr: str)
        }
    }
    
    func createAction(isBlockingRule: Bool) -> Action {
        // for now we have to only worry aboyt two types of actions: block and ignore-previous-rules. No selector for now. And perhaps only for CSS.
        return Action(isBlockingRule: isBlockingRule)
    }
    
    func resolveOptions(optStr: String) throws {
        let options: [String] = optStr.components(separatedBy: ",").map({$0.trimmingCharacters(in: .whitespacesAndNewlines)})
        for option in options {
            var negatedResources: Set<ResourceTypes> = []
            switch option.hasPrefix("~") {
            case true: //exceptions
                var mutableStr = option
                mutableStr.removeFirst(1)
                switch getOptionType(prop: mutableStr) {
                case (.resource, let val):
                    let cleanVal = val as! ResourceTypes
                    _ = cleanVal != .raw ? negatedResources.insert(cleanVal) : nil
                case (.load, _):
                    loadType = [LoadTypes.firstParty]
                case (.caseSensitive, let val):
                    urlFilterIsCaseSensitive = !(val as! Bool)
                case (.unknown, _):
                    throw NSError(domain: "Unkown Option", code: 0, userInfo: nil)
                default:
                    break
                }
            default:
                switch getOptionType(prop: option) {
                case (.resource, let val):
                    resourceType == nil ? resourceType = [] : nil
                    resourceType?.insert(val as! ResourceTypes)
                case (.load, _):
                    loadType = [LoadTypes.thirdParty]
                case (.caseSensitive, let val):
                    urlFilterIsCaseSensitive = (val as! Bool)
                case (.domain, let val):
                    
                    let domains = ((val as? String) ?? "").components(separatedBy: "|")
                    var allowedDomains: [String] = []
                    var blockedDomains: [String] = []
                    domains.forEach({
                        switch $0 {
                        case var val where val.hasPrefix("~"):
                            val.removeFirst(1)
                            blockedDomains.append("*\(val.punyCode())")
                        default:
                            allowedDomains.append("*\($0.punyCode())")
                        }
                    })
                    ifDomain = allowedDomains.count > 0 ? allowedDomains : nil
                    unlessDomain = blockedDomains.count > 0 ? blockedDomains : nil
                case (.unknown, _):
                    throw NSError(domain: "Unkown Option", code: 0, userInfo: nil)
                }
            }
            (resourceType == nil && negatedResources.count > 0) ? resourceType = resources.subtracting(negatedResources) : nil
        }
    }
    
    typealias OptionTuple = (optType: OptionType,val: Any?)
    private func getOptionType(prop: String) -> OptionTuple {
        switch prop {
        case EasyListOptions.thirdParty.rawValue:
            return (.load, nil)
        case EasyListOptions.image.rawValue:
            return (.resource, ResourceTypes.image)
        case EasyListOptions.script.rawValue:
            return (.resource, ResourceTypes.script)
        case EasyListOptions.popup.rawValue:
            return (.resource, ResourceTypes.popup)
        case EasyListOptions.font.rawValue:
            return (.resource, ResourceTypes.font)
        case EasyListOptions.stylesheet.rawValue:
            return (.resource, ResourceTypes.styleSheet)
        case EasyListOptions.media.rawValue, EasyListOptions.object.rawValue:
            return (.resource, ResourceTypes.media)
        case EasyListOptions.other.rawValue,
             EasyListOptions.objectSubrequest.rawValue,
             EasyListOptions.ping.rawValue,
             EasyListOptions.webrtc.rawValue,
             EasyListOptions.websocket.rawValue,
             EasyListOptions.xmlhttprequest.rawValue:
            return (.resource, ResourceTypes.raw)
        case EasyListOptions.matchcase.rawValue:
            return (.caseSensitive, true)
        case EasyListOptions.subdocument.rawValue:
            return (.resource, ResourceTypes.document)
        case let x where x.hasPrefix("domain"):
            return (.domain, x.components(separatedBy: "=")[1])
        default:
            return (.unknown, nil)
        }
    }
    
    func resolveURLFitler(urlStr: String) {
        
        var hasDomainSpecifier: Bool = false
        var hasStartOfAddressSpecifier: Bool = false
        var hasEndOfAddressSpecifier: Bool = false
        var hasEndSeparatorSpecifier: Bool = false
        var mutableStr: String = urlStr
        scheme = "\(RegexSpecifiers.scheme.rawValue)"
        
        // Identify start characteristics
        if urlStr.hasPrefix("||") {
            mutableStr.removeFirst(2)
            hasDomainSpecifier = true
        } else if urlStr.hasPrefix("|") {
            mutableStr.removeFirst(1)
            hasStartOfAddressSpecifier = true
        }
        
        // Identify end characteristics
        if urlStr.hasSuffix("^") {
            mutableStr.removeLast(1)
            hasEndSeparatorSpecifier = true
        } else if urlStr.hasSuffix("|") {
            mutableStr.removeLast(1)
            hasEndOfAddressSpecifier = true
        }
        
        func getDomain(string: String, startIndex: String.Index, endIndex: String.Index) -> String {
            let domainEndIndex: String.Index = string.range(of: "[/^]", options: .regularExpression, range: Range(uncheckedBounds: (startIndex, endIndex)), locale: nil)?.lowerBound ?? string.endIndex
            return String(string[Range(uncheckedBounds: (string.startIndex, domainEndIndex))])
            
        }
        
        if hasDomainSpecifier || hasStartOfAddressSpecifier {
            if let rangeScheme = mutableStr.range(of: "^\(RegexSpecifiers.scheme.rawValue)", options: .regularExpression, range: nil, locale: nil) {
                
                scheme = String(mutableStr[rangeScheme])
                let tempString = mutableStr.replacingOccurrences(of: scheme!, with: "")
                let tempDomain = getDomain(string: tempString, startIndex: tempString.startIndex, endIndex: tempString.endIndex)
                let punyCoded = tempDomain.punyCode()
                mutableStr = mutableStr.replacingOccurrences(of: tempDomain, with: punyCoded)
                domain = punyCoded
            } else {
                let tempDomain = getDomain(string: mutableStr, startIndex: mutableStr.startIndex, endIndex: mutableStr.endIndex)
                let punyCoded = tempDomain.punyCode()
                mutableStr = mutableStr.replacingOccurrences(of: tempDomain, with: punyCoded)
                domain = punyCoded
            }
        }
        
        
        mutableStr = mutableStr.reduce(into: "", {
            switch $1 {
            case "*":
                return $0 += RegexSpecifiers.wildcard.rawValue
            case "^":
                return $0 += RegexSpecifiers.separator.rawValue
            case "|", "+", ".", "?", "&" , "(" , ")", "{", "}", "[", "]":
                return $0 += "\\\\" + "\($1)"
            case "/":
                return $0 += "/"
            case "%":
                return $0 += "%"
            default:
                return $0 += "\($1)".encodeURI()
            }
        })
        
        // Get path here:
        if domain == nil || domain!.isEmpty {
            path = mutableStr
        } else if domain != nil {
            if let rangeDomain = mutableStr.range(of: domain!, options: [.literal, .caseInsensitive], range: nil, locale: nil) {
                let tempPath = String(mutableStr[rangeDomain.upperBound..<mutableStr.endIndex])
                !tempPath.isEmpty ? path = tempPath : nil
            }
        }

        if hasStartOfAddressSpecifier {
            urlFilter = "^\(mutableStr)"
        } else if hasDomainSpecifier {
            urlFilter = "^\(scheme!)\(RegexSpecifiers.domain.rawValue)\(mutableStr)"
        } else {
            urlFilter = "^\(RegexSpecifiers.scheme.rawValue).*\(mutableStr)"
        }
        
        if hasEndOfAddressSpecifier {
            urlFilter += "$"
        } else if hasEndSeparatorSpecifier {
            urlFilter += RegexSpecifiers.endSeparator.rawValue
        }
    }
    
    func jsonify() -> String {
        return "\"trigger\":{\"url-filter\": \"\(urlFilter)\""
            + (urlFilterIsCaseSensitive == nil ? "" : ",\"url-filter-is-case-sensitive\": \(urlFilterIsCaseSensitive!)")
            + (ifDomain == nil ? "" : ",\"if-domain\": [\"\(ifDomain!.joined(separator: "\", \""))\"]")
            + (unlessDomain == nil ? "" : ",\"unless-domain\": [\"\(unlessDomain!.joined(separator: "\", \""))\"]")
            + (resourceType == nil ? "" : ",\"resource-type\": [\"\(resourceType!.map({$0.rawValue}).joined(separator: "\", \""))\"]")
            + (loadType == nil ? "" : ",\"load-type\": [\"\(loadType!.map({$0.rawValue}).joined(separator: "\", \""))\"]")
            + (ifTopUrl == nil ? "" : ",\"if-top-url\": [\"\(ifTopUrl!.joined(separator: "\", \""))\"]")
            + (unlessTopUrl == nil ? "" : ",\"unless-top-url\": [\"\(unlessTopUrl!.joined(separator: "\", \""))\"]") + "}"
    }
}

enum ActionType: String {
    case block = "block"
    case blockCookies = "block-cookies"
    case cssDisplayNone = "css-display-none"
    case ignorePreviousRules = "ignore-previous-rules"
    case makeHttps = "make-https"
}

class Action: Hashable, JSONRepresentable {
    static func == (lhs: Action, rhs: Action) -> Bool {
        return lhs.type == rhs.type && lhs.selector == rhs.selector
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(type)
        hasher.combine(selector)
    }
    
    
    var type: ActionType
    //TODO:- Create logic for other types and adding selectors from EasyList.
    var selector: String?
    
    init(isBlockingRule: Bool) {
        type = isBlockingRule ? ActionType.block : ActionType.ignorePreviousRules
        selector = nil
    }
    
    func jsonify() -> String {
        return "\"action\":{\"type\": \"\(type.rawValue)\"" + (selector == nil ? "" : ",\"selector\": \"\(selector!)\"") + "}"
    }
}

let cli = CommandLineKit.CommandLine()


let inputFileURL = StringOption(shortFlag: "i", longFlag: "Input file", required: true,
                                helpMessage: "Path to the input file.")
let outputFileURL = StringOption(shortFlag: "o", longFlag: "Output file", required: true,
                                 helpMessage: "Path to the output file.")

cli.addOptions(inputFileURL, outputFileURL)

do {
    try cli.parse()
} catch {
    cli.printUsage(error)
    exit(EX_USAGE)
}

var fileContent: String?
do {
    fileContent = try! String(contentsOfFile: inputFileURL.value!)
}

var outputString: String = "[\n"
var outputComponents: [String] = []
var output: [RuleIdentifier] = []

var blockRules: [Rule] = []
var cssRules: [Rule] = []
var exceptionRules: [Rule] = []

var blockJSON: [String] = []
var exceptionJSON: [String] = []
var cssJSON: [String] = []

var components = fileContent!.components(separatedBy: CharacterSet.newlines)
for i in 0..<components.count {
    if let rule = Rule(str: components[i]) {
        switch rule.action.type {
        case .block:
            blockRules.append(rule)
            blockJSON.append(rule.jsonify())
        case .ignorePreviousRules:
            exceptionRules.append(rule)
            exceptionJSON.append(rule.jsonify())
        case .cssDisplayNone:
            cssRules.append(rule)
            cssJSON.append(rule.jsonify())
        default:
            break
        }
    }
}


//TODO: Merging here
//let d = Dictionary(grouping: output, by: {$0})
//    let groups = d.filter({$1.count > 1})
////groups.forEach({print("key: \($0)")})
//var count = 0
//groups.forEach({ count = max($0.value.count, count)})
////print(count)

outputString += [cssJSON.joined(separator: ",\n"),blockJSON.joined(separator: ",\n"),exceptionJSON.joined(separator: ",\n")].joined(separator: ",\n")

outputString += "]"

try! outputString.write(toFile: outputFileURL.value!, atomically: true, encoding: .utf8)
