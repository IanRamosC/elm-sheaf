const STYLES = { bold: 1, red: 31, green: 32, yellow: 33 } as const;

export type Style = keyof typeof STYLES;

/** Colour only helps a person reading a terminal, and `NO_COLOR` is their way to opt out. */
export function supportsColour(): boolean {
  return process.stdout.isTTY === true && !process.env.NO_COLOR;
}

export function paint(style: Style, text: string, colour: boolean): string {
  return colour ? `\u001b[${STYLES[style]}m${text}\u001b[0m` : text;
}
