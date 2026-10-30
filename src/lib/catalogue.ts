export type BookMetadata = {
  isbn13: string;
  title: string;
  authors: string[];
  publisher: string;
  edition: string;
  publicationYear: string;
  languageCode: string;
  description: string;
  coverImageUrl: string;
  metadataSource: string;
  metadataSourceId: string;
};

function isbn13CheckDigit(firstTwelve: string): string {
  const sum = [...firstTwelve].reduce((total, digit, index) =>
    total + Number(digit) * (index % 2 === 0 ? 1 : 3), 0);
  return String((10 - (sum % 10)) % 10);
}

export function normalizeIsbn(input: string): string {
  const compact = input.trim().replace(/[\s-]/g, "").toUpperCase();
  if (/^\d{13}$/.test(compact)) {
    if (isbn13CheckDigit(compact.slice(0, 12)) !== compact[12]) {
      throw new Error("The ISBN-13 check digit is not valid.");
    }
    return compact;
  }
  if (/^\d{9}[\dX]$/.test(compact)) {
    const sum = [...compact].reduce((total, char, index) =>
      total + (char === "X" ? 10 : Number(char)) * (10 - index), 0);
    if (sum % 11 !== 0) throw new Error("The ISBN-10 check digit is not valid.");
    const firstTwelve = "978" + compact.slice(0, 9);
    return firstTwelve + isbn13CheckDigit(firstTwelve);
  }
  throw new Error("Enter a valid ISBN-10 or ISBN-13.");
}

type OpenLibraryBook = {
  title?: string;
  authors?: Array<{ name?: string }>;
  publishers?: Array<{ name?: string }>;
  publish_date?: string;
  edition_name?: string;
  languages?: Array<{ key?: string }>;
  cover?: { large?: string; medium?: string; small?: string };
  notes?: string | { value?: string };
};

export async function fetchOpenLibraryMetadata(isbnInput: string): Promise<BookMetadata> {
  const isbn13 = normalizeIsbn(isbnInput);
  const url = new URL("https://openlibrary.org/api/books");
  url.searchParams.set("bibkeys", "ISBN:" + isbn13);
  url.searchParams.set("jscmd", "data");
  url.searchParams.set("format", "json");
  const response = await fetch(url, {
    headers: { Accept: "application/json", "User-Agent": "ShelfShare/0.1 (human-facing book catalogue)" },
    signal: AbortSignal.timeout(9000),
  });
  if (response.status === 404) throw new Error("No catalogue record was found for this ISBN. Enter the book details manually.");
  if (response.status === 429) throw new Error("The book metadata provider is busy. Please wait or enter the details manually.");
  if (!response.ok) throw new Error("Book metadata could not be retrieved. You can still enter the details manually.");
  const body = await response.json() as Record<string, OpenLibraryBook>;
  const book = body["ISBN:" + isbn13];
  if (!book) throw new Error("No catalogue record was found for this ISBN. Enter the book details manually.");
  const yearMatch = book.publish_date?.match(/\b(1[4-9]\d{2}|20\d{2}|21\d{2}|2200)\b/);
  const languageKey = book.languages?.[0]?.key ?? "";
  const languageCode = languageKey.split("/").filter(Boolean).pop() ?? "";
  const notes = typeof book.notes === "string" ? book.notes : book.notes?.value ?? "";
  return {
    isbn13,
    title: book.title ?? "",
    authors: (book.authors ?? []).map((item) => item.name ?? "").filter(Boolean),
    publisher: book.publishers?.[0]?.name ?? "",
    edition: book.edition_name ?? "",
    publicationYear: yearMatch?.[1] ?? "",
    languageCode,
    description: notes.slice(0, 4000),
    coverImageUrl: book.cover?.large ?? book.cover?.medium ?? book.cover?.small ?? "",
    metadataSource: "openlibrary",
    metadataSourceId: isbn13,
  };
}

/** Re-encodes a camera/file image to JPEG through Canvas, dropping EXIF metadata. */
export async function sanitiseListingPhoto(file: File): Promise<Blob> {
  if (!file.type.startsWith("image/")) throw new Error("Choose an image file.");
  if (file.size > 12 * 1024 * 1024) throw new Error("Each photo must be 12 MB or smaller.");
  const bitmap = await createImageBitmap(file);
  try {
    if (bitmap.width < 320 || bitmap.height < 320) throw new Error("Photos must be at least 320 × 320 pixels.");
    const maxEdge = 1800;
    const scale = Math.min(1, maxEdge / Math.max(bitmap.width, bitmap.height));
    const canvas = document.createElement("canvas");
    canvas.width = Math.max(1, Math.round(bitmap.width * scale));
    canvas.height = Math.max(1, Math.round(bitmap.height * scale));
    const context = canvas.getContext("2d");
    if (!context) throw new Error("This browser could not prepare the photo.");
    context.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
    const blob = await new Promise<Blob>((resolve, reject) => {
      canvas.toBlob((result) => result ? resolve(result) : reject(new Error("Photo conversion failed.")), "image/jpeg", 0.88);
    });
    return blob;
  } finally {
    bitmap.close();
  }
}
