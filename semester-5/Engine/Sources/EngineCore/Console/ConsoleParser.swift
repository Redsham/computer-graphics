// MARK: - Console parsing

public enum ConsoleParser {
    public static func tokenize(_ input: String) throws -> [String] {
        var words: [String] = []
        var word = ""
        var quote: Character?
        var escaping = false
        var started = false

        for character in input {
            if escaping {
                word.append(character)
                escaping = false
                started = true
            } else if character == "\\" {
                escaping = true
                started = true
            } else if let current = quote {
                if character == current {
                    quote = nil
                } else {
                    word.append(character)
                }
            } else if character == "\"" || character == "'" {
                quote = character
                started = true
            } else if character.isWhitespace {
                if started {
                    words.append(word)
                    word = ""
                    started = false
                }
            } else {
                word.append(character)
                started = true
            }
        }

        guard quote == nil, !escaping else {
            throw EngineError.invalidConfiguration("Unclosed quote or escape in command.")
        }

        if started {
            words.append(word)
        }

        return words
    }
}
