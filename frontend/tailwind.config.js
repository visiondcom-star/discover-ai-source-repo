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
        primary: 'var(--primary-color, #006233)',
        secondary: 'var(--secondary-color, #FFFFFF)',
        brand: {
          DEFAULT: '#006233',
          dark: '#004D28',
          bright: '#1E8B52',
          tint: '#E6F2EC',
          50: '#F0F9F4',
          100: '#E1F3E9',
          500: '#1E8B52',
          700: '#006233',
          900: '#003B1E',
        },
        accent: {
          DEFAULT: '#F2A948',
          light: '#FDEED8',
          dark: '#D97706',
        },
        canvas: '#F7F6F3',
        ink: {
          DEFAULT: '#222222',
          soft: '#6C757D',
          muted: '#9C9C9C',
        },
      },
      fontFamily: {
        sans: ['Poppins', 'system-ui', '-apple-system', 'sans-serif'],
        poppins: ['Poppins', 'sans-serif'],
      },
      boxShadow: {
        card: '0 4px 20px -2px rgba(0, 0, 0, 0.05)',
        float: '0 12px 32px -4px rgba(0, 0, 0, 0.12)',
      },
    },
  },
  plugins: [],
};
