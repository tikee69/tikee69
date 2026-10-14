import Accelerate
import Foundation

/// Calculs sur les empreintes d'images (vecteurs de nombres).
enum VectorMath {
    static func normalized(_ v: [Float]) -> [Float] {
        guard !v.isEmpty else { return v }
        let norm = sqrt(vDSP.sumOfSquares(v))
        guard norm > 0, norm.isFinite else { return v }
        return vDSP.divide(v, norm)
    }

    /// Ressemblance entre deux empreintes normalisées : 1 = identiques, 0 = sans rapport.
    static func similarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        return vDSP.dot(a, b)
    }

    static func data(from v: [Float]) -> Data {
        v.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static func vector(from data: Data) -> [Float] {
        let count = data.count / MemoryLayout<Float>.size
        guard count > 0 else { return [] }
        var out = [Float](repeating: 0, count: count)
        out.withUnsafeMutableBytes { dest in
            _ = data.copyBytes(to: dest, count: count * MemoryLayout<Float>.size)
        }
        return out
    }

    /// Calcule toutes les ressemblances entre `queries` et `base` d'un coup (multiplication de matrices).
    /// Résultat : tableau à plat, ligne i = query i, colonne j = base j.
    static func similarityMatrix(queries: [[Float]], base: [[Float]], dimension: Int) -> [Float] {
        let m = queries.count
        let n = base.count
        guard m > 0, n > 0, dimension > 0 else { return [] }

        var a = [Float]()
        a.reserveCapacity(m * dimension)
        for q in queries { a.append(contentsOf: q.count == dimension ? q : [Float](repeating: 0, count: dimension)) }

        // base transposée : dimension × n
        var bRows = [Float]()
        bRows.reserveCapacity(n * dimension)
        for b in base { bRows.append(contentsOf: b.count == dimension ? b : [Float](repeating: 0, count: dimension)) }
        var bT = [Float](repeating: 0, count: n * dimension)
        vDSP_mtrans(bRows, 1, &bT, 1, vDSP_Length(dimension), vDSP_Length(n))

        var c = [Float](repeating: 0, count: m * n)
        vDSP_mmul(a, 1, bT, 1, &c, 1, vDSP_Length(m), vDSP_Length(n), vDSP_Length(dimension))
        return c
    }

    /// Petit hachage stable (identique d'un lancement à l'autre), pour un ordre aléatoire mais fixe.
    static func stableHash(_ s: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in s.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}
