/** @type {import('tailwindcss').Config} */
export default {
    content: ['./index.html', './src/**/*.{js,jsx,ts,tsx}'],
    theme: {
        extend: {
            colors: {
                brand: {
                    50: '#fcfaf5',
                    100: '#f8f4ec',
                    200: '#efdfc2',
                    300: '#e5c998',
                    400: '#dbb46e',
                    500: '#d4af37',  // Primary Luxury Gold
                    600: '#b4952f',
                    700: '#947a27',
                    800: '#755e1a',
                    900: '#554313',
                },
                surface: {
                    DEFAULT: '#0B0B0B',  // Deep Black Background
                    card: '#141414',     // Slightly lighter for cards
                    border: 'rgba(212,175,55,0.35)', // Gold tinted borders
                },
            },
            fontFamily: {
                sans: ['Inter', 'system-ui', 'sans-serif'],
                display: ['Outfit', 'system-ui', 'sans-serif'],
            },
            animation: {
                'fade-in': 'fadeIn 0.3s ease-in-out',
                'slide-up': 'slideUp 0.3s ease-out',
                'pulse-slow': 'pulse 3s cubic-bezier(0.4, 0, 0.6, 1) infinite',
            },
            keyframes: {
                fadeIn: { from: { opacity: 0 }, to: { opacity: 1 } },
                slideUp: { from: { opacity: 0, transform: 'translateY(10px)' }, to: { opacity: 1, transform: 'translateY(0)' } },
            },
        },
    },
    plugins: [],
};
