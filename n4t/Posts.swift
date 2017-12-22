import Foundation

extension String: Error {}

struct Posts: Codable {
    let filename: String
    let ext: String
    let tim: Int
    let time: Int
    let semantic_url: String

    enum CodingKeys: String, CodingKey {
        case filename = "filename"
        case ext = "ext"
        case tim = "tim"
        case time = "time"
        case semantic_url = "semantic_url"
    }

    init(json: [String: Any]) throws {

        debugPrint(json)

        guard let filename = json["filename"] as? String,
              let ext = json["ext"] as? String,
              let tim = json["tim"] as? Int,
              let time = json["time"] as? Int,
              let semantic_url = json["semantic_url"] as? String else {
            debugPrint("cannot decode json")
            throw "Something Broke!"
        }
        self.filename = filename
        self.ext = ext
        self.tim = tim
        self.time = time
        self.semantic_url = semantic_url
    }
}
