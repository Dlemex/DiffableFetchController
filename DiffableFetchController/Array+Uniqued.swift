//
//  Array+Uniqued.swift
//  RentalManager
//
//  Created by David Edwards on 8/1/19.
//  Copyright © 2019 Tech For Tomorrow, Inc. All rights reserved.
//

import Foundation

public extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
