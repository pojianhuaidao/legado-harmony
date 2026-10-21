import UnsupportedOperationException from '../UnsupportedOperationException';
import CharacterSetECI from '../common/CharacterSetECI';
import {TextDecoder,TextEncoder} from '@zxing/text-encoding'

/**
 * Responsible for en/decoding strings.
 */
export default class StringEncoding {

  /**
   * Allows the user to set a custom decoding function
   * so more encoding formats the native ones can be supported.
   */
  public static customDecoder: (bytes: Uint8Array, encodingName: string) => string;

  /**
   * Allows the user to set a custom encoding function
   * so more encoding formats the native ones can be supported.
   */
  public static customEncoder: (s: string, encodingName: string) => Uint8Array;

  /**
   * Decodes some Uint8Array to a string format.
   */
  public static decode(bytes: Uint8Array, encoding: string | CharacterSetECI): string {

    const encodingName = this.encodingName(encoding);
    const normalized = this.normalizeEncodingName(encodingName);

    if (this.customDecoder) {
      return this.customDecoder(bytes, encodingName);
    }

    // Handle ISO-8859-1 (Latin1) explicitly: one-to-one mapping byte -> codepoint
    const encUpper = encodingName ? encodingName.toUpperCase() : '';
    if (encUpper === 'ISO-8859-1' || encUpper === 'ISO_8859_1' || encUpper === 'ISO8859_1' || encUpper === 'ISO8859-1') {
      // build string in chunks to avoid apply null limitations
      const CHUNK = 0x8000;
      let res = '';
      for (let i = 0; i < bytes.length; i += CHUNK) {
        const chunk = bytes.subarray(i, Math.min(i + CHUNK, bytes.length));
        const chars: string[] = [];
        for (let j = 0; j < chunk.length; j++) {
          chars.push(String.fromCharCode(chunk[j]));
        }
        res += chars.join('');
      }
      return res;
    }

    // Increases browser support. Try TextDecoder with normalized name first.
    if (typeof TextDecoder === 'undefined' || this.shouldDecodeOnFallback(encodingName)) {
      return this.decodeFallback(bytes, encodingName);
    }

    try {
      return new TextDecoder(normalized).decode(bytes);
    } catch (e) {
      // fallback
      return this.decodeFallback(bytes, encodingName);
    }
  }

  /**
   * Checks if the decoding method should use the fallback for decoding
   * once Node TextDecoder doesn't support all encoding formats.
   *
   * @param encodingName
   */
  private static shouldDecodeOnFallback(encodingName: string): boolean {
    return !StringEncoding.isBrowser() && encodingName === 'ISO-8859-1';
  }

  /**
   * Encodes some string into a Uint8Array.
   */
  public static encode(s: string, encoding: string | CharacterSetECI): Uint8Array {

    const encodingName = this.encodingName(encoding);
    const normalized = this.normalizeEncodingName(encodingName);

    if (this.customEncoder) {
      return this.customEncoder(s, encodingName);
    }

    // Increases browser support.
    // Handle single-byte encodings explicitly (Latin1 / ISO-8859-1 and ASCII)
    const encLower = encodingName ? encodingName.toUpperCase() : '';
    if (encLower === 'ISO-8859-1' || encLower === 'ISO_8859_1' || encLower === 'ISO8859_1' || encLower === 'ISO8859-1') {
      const out = new Uint8Array(s.length);
      for (let i = 0; i < s.length; i++) {
        out[i] = s.charCodeAt(i) & 0xFF;
      }
      return out;
    }

    // If TextEncoder is not available, use a fallback implementation that supports UTF-8
    // If TextEncoder polyfill supports specifying encoding, try it with normalized name.
    if (typeof TextEncoder !== 'undefined') {
      try {
        // Some TextEncoder polyfills accept an encoding label
        // @ts-ignore
        const te = new TextEncoder(normalized);
        // @ts-ignore
        const encoded = te.encode(s);
        if (encoded && encoded.length > 0) return encoded;
      } catch (e) {
        // ignore and fall back
      }
    }

    // If TextEncoder not usable or doesn't support the encoding, use fallback for UTF-8
    if (encLower === 'UTF-8' || encLower === 'UTF8' || encLower === 'UNICODE') {
      if (typeof TextEncoder !== 'undefined') {
        return new TextEncoder().encode(s);
      }
      return this.encodeFallback(s, encodingName);
    }

    // Last resort: try encodeFallback which will throw for unsupported encodings
    return this.encodeFallback(s, encodingName);
  }

  private static isBrowser(): boolean {
    return false;
  }

  /**
   * Returns the string value from some encoding character set.
   */
  public static encodingName(encoding: string | CharacterSetECI): string {
    return typeof encoding === 'string'
      ? encoding
      : encoding.getName();
  }

  /**
   * Returns character set from some encoding character set.
   */
  public static encodingCharacterSet(encoding: string | CharacterSetECI): CharacterSetECI {

    if (encoding instanceof CharacterSetECI) {
      return encoding;
    }

    return CharacterSetECI.getCharacterSetECIByName(encoding);
  }

  /**
   * Runs a fallback for the native decoding funcion.
   */
  private static decodeFallback(bytes: Uint8Array, encoding: string | CharacterSetECI): string {

    const characterSet = this.encodingCharacterSet(encoding);

    if (StringEncoding.isDecodeFallbackSupported(characterSet)) {

      let s = '';

      for (let i = 0, length = bytes.length; i < length; i++) {

        let h = bytes[i].toString(16);

        if (h.length < 2) {
          h = '0' + h;
        }

        s += '%' + h;
      }

      return decodeURIComponent(s);
    }

    if (characterSet.equals(CharacterSetECI.UnicodeBigUnmarked)) {
      return String.fromCharCode.apply(null, new Uint16Array(bytes.buffer));
    }

    throw new UnsupportedOperationException(`Encoding ${this.encodingName(encoding)} not supported by fallback.`);
  }

  private static isDecodeFallbackSupported(characterSet: CharacterSetECI) {
    return characterSet.equals(CharacterSetECI.UTF8) ||
      characterSet.equals(CharacterSetECI.ISO8859_1) ||
      characterSet.equals(CharacterSetECI.ASCII);
  }

  /**
   * Runs a fallback for the native encoding funcion.
   *
   * @see https://stackoverflow.com/a/17192845/4367683
   */
  private static encodeFallback(s: string, encodingName?: string): Uint8Array {
    const encLower = encodingName ? encodingName.toUpperCase() : '';

    // Support ISO-8859-1 via simple charCode mapping
    if (encLower === 'ISO-8859-1' || encLower === 'ISO_8859_1' || encLower === 'ISO8859_1' || encLower === 'ISO8859-1') {
      const out = new Uint8Array(s.length);
      for (let i = 0; i < s.length; i++) {
        out[i] = s.charCodeAt(i) & 0xFF;
      }
      return out;
    }

    // UTF-8 fallback using encodeURIComponent/unescape trick
    if (encLower === 'UTF-8' || encLower === 'UTF8' || encLower === '' ) {
      const encoded = unescape(encodeURIComponent(s));
      const arr = new Uint8Array(encoded.length);
      for (let i = 0; i < encoded.length; i++) {
        arr[i] = encoded.charCodeAt(i);
      }
      return arr;
    }

    throw new UnsupportedOperationException(`Encoding ${encodingName} not supported by encodeFallback.`);
  }

  private static normalizeEncodingName(name: string): string {
    if (!name) return name;
    const n = name.trim().toLowerCase();
    if (n === 'gb2312' || n === 'gbk' || n === 'gb18030') return 'gb18030';
    if (n === 'shift_jis' || n === 'sjis' || n === 'shift-jis' || n === 'shift jis') return 'shift_jis';
    if (n === 'iso8859_1' || n === 'iso-8859-1' || n === 'iso8859-1' || n === 'iso_8859_1') return 'iso-8859-1';
    if (n === 'utf8' || n === 'utf-8' || n === 'unicode') return 'utf-8';
    return name;
  }
}
