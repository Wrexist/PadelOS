import Foundation

/// Translation lookup for text produced by the shared package (validation messages,
/// scoring rejections, summaries). Keys are the English text with printf-style
/// placeholders (`%lld` for integers, `%@` for text). Translations live in the app's
/// string catalog, so lookups use the main bundle; without a translation (English,
/// tests on Linux) the key itself is the text.
public enum L10n {
    public static func string(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    public static func format(_ key: String, _ arguments: any CVarArg...) -> String {
        String(format: string(key), locale: .current, arguments: arguments)
    }
}
