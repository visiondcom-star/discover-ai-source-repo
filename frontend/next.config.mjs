/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'standalone',
  // Next.js 16 dev server blocks cross-origin requests to /_next/* assets.
  // Inside Docker, the browser (Playwright) loads the app via the
  // docker-network hostname "frontend", so module scripts send
  // "Origin: http://frontend:3000" which must be allow-listed or every
  // chunk request returns 403 and the app never hydrates.
  allowedDevOrigins: ['frontend'],
  async rewrites() {
    return [
      {
        source: '/api/:path*',
        destination: `${process.env.BACKEND_URL || 'http://localhost:8000'}/api/:path*`,
      },
    ];
  },
};

export default nextConfig;