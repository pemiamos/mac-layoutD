import Foundation

public enum ChineseLineBreakRules {
    public static let forbiddenLineStartCharacters = Set<Character>(
        "，。、！？：；）】〕》〉」』”’、,.!?:;)]}%"
    )

    public static let forbiddenLineEndCharacters = Set<Character>(
        "（【〔《〈「『“‘([{"
    )

    public static func forbidsLineStart(_ character: Character) -> Bool {
        forbiddenLineStartCharacters.contains(character)
    }

    public static func forbidsLineEnd(_ character: Character) -> Bool {
        forbiddenLineEndCharacters.contains(character)
    }
}
