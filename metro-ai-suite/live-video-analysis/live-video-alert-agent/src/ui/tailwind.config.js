/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    "./index.html",
    "./static/js/app.js",
  ],
  safelist: [
    // Dynamically constructed classes in app.js (colors object in showToast)
    "bg-green-500",
    "bg-red-500",
    "bg-blue-500",
  ],
  theme: {
    extend: {},
  },
  plugins: [],
}

