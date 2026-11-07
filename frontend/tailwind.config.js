/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    './src/pages/**/*.{js,ts,jsx,tsx,mdx}',
    './src/components/**/*.{js,ts,jsx,tsx,mdx}',
    './src/app/**/*.{js,ts,jsx,tsx,mdx}',
  ],
  theme: {
    extend: {
      colors: {
        primary: 'var(--primary-color, #0F4C3A)',
        secondary: 'var(--secondary-color, #FFFFFF)',
        brand: {
          DEFAULT: '#0F4C3A',
          dark: '#063828',
          bright: '#1E8B52',
          tint: '#EAF3EE',
          50: '#F0F9F4',
          100: '#E1F3E9',
          500: '#1E8B52',
          700: '#0F4C3A',
          900: '#063828',
        },
        accent: {
          DEFAULT: '#F2A948',
          light: '#FDEED8',
          dark: '#D97706',
        },
        canvas: '#FAF6EE',
        ink: {
          DEFAULT: '#13221C',
          soft: '#5A6B63',
          muted: '#9C9C9C',
        },
      },
      fontFamily: {
        sans: ['Poppins', 'system-ui', '-apple-system', 'sans-serif'],
        poppins: ['Poppins', 'sans-serif'],
        display: ['Fraunces', 'Georgia', 'serif'],
      },
      boxShadow: {
        card: '0 4px 20px -2px rgba(0, 0, 0, 0.05)',
        float: '0 12px 32px -4px rgba(0, 0, 0, 0.12)',
      },
    },
  },
  plugins: [],
};
