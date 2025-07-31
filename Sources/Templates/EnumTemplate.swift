// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation
import SourceryFramework
import SourceryRuntime

class EnumTemplate {
    func render(_ types: Types, arguments: [String]) -> String {
        var output = "// Generated using Sourcery\n"
        output += "// DO NOT EDIT\n\n"
        
        // 只处理标记了 AutoEquatable 的枚举
        for type in types.enums where type.isAutoEquatable {
            output += generateEnumExtension(type)
            output += "\n\n"
        }
        
        return output
    }
    
    private func generateEnumExtension(_ type: Type) -> String {
        var output = "// MARK: - \(type.name) + Generated\n"
        output += "extension \(type.name) {\n"
        
        // 为每个 case 生成属性
        if let enumType = type as? Enum {
            output += generateStringHandling(enumType)
        }
        
        output += "}\n"
        return output
    }
    
    private func generateStringHandling(_ enumType: Enum) -> String {
        var output = ""
        
        // 检查是否有 String 类型的关联值
        let stringCases = enumType.cases.filter { enumCase in
            guard let associatedValue = enumCase.associatedValues.first else { return false }
            return associatedValue.typeName.name == "String"
        }
        
        if !stringCases.isEmpty {
            // 生成 stringValue 属性
            output += "    var stringValue: String? {\n"
            output += "        switch self {\n"
            
            for enumCase in stringCases {
                output += "        case .\(enumCase.name)(let value):\n"
                output += "            return value\n"
            }
            
            output += "        default:\n"
            output += "            return nil\n"
            output += "        }\n"
            output += "    }\n\n"
            
            // 生成 isStringEmpty 属性
            output += "    var isStringEmpty: Bool {\n"
            output += "        return stringValue?.isEmpty ?? true\n"
            output += "    }\n\n"
            
            // 生成 safeString 方法
            output += "    func safeString(default defaultValue: String = \"\") -> String {\n"
            output += "        return stringValue ?? defaultValue\n"
            output += "    }\n"
        }
        
        return output
    }
}

// 辅助扩展
extension Type {
    var isAutoEquatable: Bool {
        return annotations["AutoEquatable"] != nil
    }
}


func decodeAssociatedEnumCaseName(enumCase: EnumCase) -> String {
    // case success(name: String)
    if let name = enumCase.associatedValues[0].localName {
        return name
    } else {
        return "value"
    }
}

func decodeAssociatedEnumCaseValue(name: String, enumCase: EnumCase) -> String {
    // 关联类型是枚举
    if enumCase.associatedValues[0].typeName.name != "String" {
        if let valueKeyName = enumCase.annotations["valueKeyName"] {
            return "\(name).\(valueKeyName)"
        } else {
            return "\(name).rawValue"
        }
    } else {
        return name
    }
}

func decodeNormalEnumValue(name: String, enumCase: EnumCase) -> String {
    if let customValue = enumCase.annotations["customValue"] as? String {
        return "\"\(customValue)\""
    } else {
        return "\"\(name)\""
    }
}

func classAndStructTypes(types: Types) -> [Type] {
    return types.all.filter { $0.isKind(of: Class.self) || $0.isKind(of: Struct.self) }
}

func typeVariables(type: Type) -> [String] {
    var variables: [String] = []
    
    var currentType: Type? = type
    
    while let _currentType = currentType {
        let list = _currentType.variables
            .filter { !$0.isComputed && !$0.isStatic && !$0.isAsync }
            .map { $0.name }
        
        variables.append(contentsOf: list)
        
        currentType = _currentType.supertype
    }
    
    return variables
}

//let test1 = classAndStructTypes(types: <#T##Types#>)
