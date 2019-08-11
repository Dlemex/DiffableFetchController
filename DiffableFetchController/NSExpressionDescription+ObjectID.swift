//
//  NSExpressionDescription+ObjectID.swift
//  RentalManager
//
//  Created by David Edwards on 8/1/19.
//  Copyright © 2019 Tech For Tomorrow, Inc. All rights reserved.
//

import CoreData

public extension NSExpressionDescription {
    
    static let objectIDKey = "objectID"
    
    static var objectID: NSExpressionDescription {
        let result = NSExpressionDescription()
        result.expression = NSExpression(expressionType: .evaluatedObject)
        result.name = objectIDKey
        result.expressionResultType = NSAttributeType.objectIDAttributeType
        return result
    }
}
