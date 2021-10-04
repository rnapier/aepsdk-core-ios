/*
 Copyright 2021 Adobe. All rights reserved.
 This file is licensed to you under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License. You may obtain a copy
 of the License at http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software distributed under
 the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
 OF ANY KIND, either express or implied. See the License for the specific language
 governing permissions and limitations under the License.
 */

import Foundation

/// Provides CRUD support for storing `Event` objects in a local database.
class EventHistory {
    var db: EventHistoryDatabase

    /// Default initializer.
    ///
    /// - Returns `nil` if the database cannot be initialized.
    init?() {
        guard let db = EventHistoryDatabase(dispatchQueue: DispatchQueue.init(label: "EventHistory")) else {
            return nil
        }

        self.db = db
    }

    /// Records an `Event` based on its calculated hash.
    ///
    /// The hash is generated based on the provided `event`'s data.
    /// The `event`'s `mask` value, if provided, will filter what values in the event data are used for hash generation.
    ///
    /// - Parameters:
    ///   - event: the `Event` to be recorded in the Event History database.
    ///   - handler: called with a `Bool` indicating a successful database insert.
    func recordEvent(_ event: Event, handler: ((Bool) -> Void)? = nil) {
        guard let hash = event.data?.fnv1a32(mask: event.mask) else {
            return
        }

        db.insert(hash: hash, handler: handler)
    }

    /// Retrieves a count of historical events matching the provided requests.
    ///
    /// - Parameters:
    ///   - requests: an array of `EventHistoryRequest`s used to generate the hash and timeframe for the event lookup
    ///   - enforceOrder: if `true`, consecutive lookups will use the oldest timestamp from the previous event as their
    ///                   from date
    ///   - handler: contains an `EventHistoryResult` for each provided request
    func getEvents(_ requests: [EventHistoryRequest], enforceOrder: Bool, handler: @escaping ([EventHistoryResult]) -> Void) {
        var results: [EventHistoryResult] = []

        if enforceOrder {
            var previousEventOldestOccurrence: Date?
            for event in requests {
                let eventHash = event.mask.fnv1a32()
                let from = previousEventOldestOccurrence ?? event.fromDate
                db.select(hash: eventHash, from: from, to: event.toDate) { result in
                    if result.count <= 0 {
                        // we have no db connection, break and call the handler
                        handler([])
                        return
                    }

                    previousEventOldestOccurrence = result.oldestOccurrence
                    results.append(result)
                }
            }
        } else {
            for event in requests {
                let eventHash = event.mask.fnv1a32()
                db.select(hash: eventHash, from: event.fromDate, to: event.toDate) { result in
                    if result.count <= 0 {
                        // we have no db connection, break and call the handler
                        handler([])
                        return
                    }

                    results.append(result)
                }
            }
        }

        handler(results)
    }

    /// Deletes events with matching hashes to those provided in `requests`.
    ///
    /// - Parameters:
    ///   - requests: an array of `EventHistoryRequest`s used to generate the hash and timeframe for the event lookup
    ///   - handler: called with the number of records deleted
    func deleteEvents(_ requests: [EventHistoryRequest], handler: ((Int) -> Void)? = nil) {
        var rowsDeleted = 0
        for request in requests {
            db.delete(hash: request.mask.fnv1a32(), from: request.fromDate, to: request.toDate) { count in
                rowsDeleted += count
            }
        }

        handler?(rowsDeleted)
    }
}
