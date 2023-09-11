import crypto from "crypto";

// 1. Encrypt a string using AES-256

function encryptAES(data: string, secretKey: Buffer): string {
  const iv = crypto.randomBytes(16);
  const cipher = crypto.createCipheriv("aes-256-cbc", secretKey, iv);
  let encrypted = cipher.update(data, "utf8", "hex");
  encrypted += cipher.final("hex");
  return `${iv.toString("hex")}${encrypted}`;
}

// 2. Asymmetrically encrypt the secret key using RSA-2048

export async function encryptRSA(publicKey: string, data: Buffer): Promise<string> {
  const encryptedBuffer = crypto.publicEncrypt(
    {
      key: publicKey,
      padding: crypto.constants.RSA_PKCS1_OAEP_PADDING,
      oaepHash: "sha1",
    },
    data,
  );
  return encryptedBuffer.toString("base64");
}

export async function encryptDataWithRSAandAES(data: string, publicKey: string) {
  // Generate a random secret key for AES encryption
  const secretKey = crypto.randomBytes(32);

  // Encrypt the data using the secret key
  const encryptedData = encryptAES(data, secretKey);

  // Encrypt the secret key using RSA
  const encryptedSecretKey = await encryptRSA(publicKey, secretKey);

  // Return the encrypted data and encrypted secret key
  return {
    encryptedData,
    aclData: encryptedSecretKey,
  };
}

// 1. Decrypt a string using AES-256
function decryptAES(encryptedData: string, secretKey: Buffer): string {
  if (encryptedData.length <= 32) {
    // Assuming hexadecimal encoding, 32 characters represent 16 bytes
    throw new Error("Invalid encrypted data format.");
  }

  const iv = Buffer.from(encryptedData.slice(0, 32), "hex");
  const encryptedText = Buffer.from(encryptedData.slice(32), "hex");

  const decipher = crypto.createDecipheriv("aes-256-cbc", secretKey, iv);
  const decryptedBuffer = Buffer.concat([decipher.update(encryptedText), decipher.final()]);

  return decryptedBuffer.toString("utf8");
}

// 2. Asymmetrically decrypt the secret key using RSA-2048

export async function decryptRSA(privateKey: string, encryptedData: string): Promise<Buffer> {
  const buffer = Buffer.from(encryptedData, "base64");
  const decryptedBuffer = crypto.privateDecrypt(
    {
      key: privateKey,
      padding: crypto.constants.RSA_PKCS1_OAEP_PADDING,
      oaepHash: "sha1",
    },
    buffer,
  );
  return decryptedBuffer;
}

export async function decryptDataWithRSAandAES(
  encryptedData: string,
  aclData: string,
  privateKey: string,
): Promise<string> {
  // Decrypt the secret key using RSA private key
  const decryptedSecretKey = await decryptRSA(privateKey, aclData);

  // Decrypt the actual data using the decrypted AES secret key
  const data = decryptAES(encryptedData, decryptedSecretKey);

  return data;
}

/**
 * Convert a Base64 encoded string to a hexadecimal string.
 *
 * @param base64String - The Base64 encoded string.
 * @returns The hexadecimal string representation of the input.
 */
export function base64ToHex(base64String: string): string {
  const raw = atob(base64String);
  let result = "";
  for (let i = 0; i < raw.length; i++) {
    const hex = raw.charCodeAt(i).toString(16);
    result += hex.length === 2 ? hex : "0" + hex;
  }
  return result;
}

/**
 * Convert a hexadecimal string to a Base64 encoded string.
 *
 * @param hexString - The hexadecimal string.
 * @returns The Base64 encoded string representation of the input.
 */
export function hexToBase64(hexString: string): string {
  if (hexString.length % 2 !== 0) {
    throw new Error("Invalid hex string");
  }

  let raw = "";
  for (let i = 0; i < hexString.length; i += 2) {
    const byte = parseInt(hexString.substr(i, 2), 16);
    raw += String.fromCharCode(byte);
  }
  return btoa(raw);
}
