declare module "emoji-picker-element" {}

declare namespace JSX {
  interface IntrinsicElements {
    "emoji-picker": React.DetailedHTMLProps<
      React.HTMLAttributes<HTMLElement>,
      HTMLElement
    >
  }
}