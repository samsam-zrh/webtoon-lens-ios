import Foundation

public enum ReadingCopy {
    public static func dialogues(_ count: Int) -> String {
        "\(count) dialogue\(count == 1 ? "" : "s")"
    }

    public static func translated(_ count: Int) -> String {
        "\(dialogues(count)) traduit\(count == 1 ? "" : "s")"
    }

    public static func pages(_ count: Int) -> String {
        "\(count) page\(count == 1 ? "" : "s")"
    }
}
