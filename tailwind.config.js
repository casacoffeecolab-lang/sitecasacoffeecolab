/** @type {import('tailwindcss').Config} */
export default {
  content: [
    './src/**/*.html',
    './src/**/*.js',
  ],
  theme: {
    // Breakpoints: mobile-first, de ~320px (Galaxy Pocket) a ultrawide (2560px+).
    screens: {
      xs: '375px',
      sm: '640px',
      md: '768px',
      lg: '1024px',
      xl: '1280px',
      '2xl': '1536px',
      '3xl': '1920px',
      '4xl': '2560px',
    },
    extend: {
      colors: {
        // Paleta da marca (legado — mantida durante a migração pro editorial)
        terracota: '#8c3a2a',
        verde: '#305429',
        cafe: '#5b3c34',
        caramelo: '#a56a3a',
        bege: '#ead8c1',
        preto: '#000000',
        branco: '#ffffff',

        // Paleta EDITORIAL (direção da dona — esboço aprovado). As variáveis CSS
        // (:root em styles.css) são a fonte da verdade pro design; estes tokens
        // expõem as cores como utilitários Tailwind (bg-paper, text-ink...).
        // NÃO expomos green/blue "flat" aqui pra não sobrescrever as escalas
        // padrão do Tailwind — essas cores vivem só nas variáveis CSS.
        paper: '#f3eee3',
        'paper-2': '#ece5d7',
        card: '#f7f2e9',
        ink: '#1b1611',
        'ink-2': '#241d16',
        'ink-3': '#14100b',
        cream: '#efe9dd',
        'cream-soft': '#b9ad97',
        muted: '#7c7160',
        coral: '#df5638',
        'coral-2': '#e86c4f',
        gold: '#c49a46',
        'gold-2': '#d6ac57',
        olive: '#3d4a31',
        'olive-soft': '#5b6743',
        line: '#ddd2bf',
      },
      fontFamily: {
        // Sora = texto/UI. titulo/decor usam placeholders (Fraunces/Caveat)
        // até termos as fontes reais (Rexton/Mayonice). Ver TODO no CLAUDE.md.
        sora: ['Sora', 'system-ui', 'sans-serif'],
        titulo: ['Fraunces', 'Georgia', 'serif'],
        decor: ['Caveat', 'cursive'],
      },
    },
  },
  plugins: [],
};
