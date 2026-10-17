export const captions = Object.freeze([
  { headline: "DIDN’T SKIP LEG DAY.\nSKIPPED FRICTION.", subtitle: "New personal best. Same two bottles." },
  { headline: "THEY SAID\nSTAY HYDRATED.", subtitle: "Diddy brought the wrong two bottles." },
  { headline: "ZERO GRIP.\nMAXIMUM DRIP.", subtitle: "The baby-oil relay team has entered the chat." },
  { headline: "RUNNING LATE?\nRUNNING LUBRICATED.", subtitle: "The only warm-up is opening both bottles." },
  { headline: "CARDIO: OPTIONAL.\nBABY OIL: PACKED.", subtitle: "A very slippery interpretation of race prep." },
  { headline: "THE TRACK IS DRY.\nHE IS NOT.", subtitle: "Somebody get this man a towel and a finish line." },
]);

export function captionText(index) {
  const caption = captions[index % captions.length];
  return `${caption.headline.replaceAll("\n", " ")}\n${caption.subtitle}\n$IMDIDDY · IMDiddy Runner`;
}
