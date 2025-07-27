import Foundation
import LLamaSwift

final class LlamaEngine {
    private let llama: LLamaSwift.LLama

    init(modelURL: URL) throws {
        let model = try LLamaSwift.Model(modelPath: modelURL.path)
        self.llama = LLamaSwift.LLama(model: model)
    }

    func generate(prompt: String,
                  maxTokens: Int32 = 120,
                  tokenHandler: @escaping (String) -> Void) async throws {
        for try await token in await llama.infer(prompt: prompt,
                                                 maxTokens: maxTokens) {
            tokenHandler(token)
        }
    }
}
