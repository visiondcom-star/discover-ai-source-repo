"use client";

export function Footer({ tenant }: { tenant: any }) {
  return (
    <footer className="bg-gray-900 text-white py-12">
      <div className="max-w-6xl mx-auto px-4">
        <div className="grid md:grid-cols-4 gap-8">
          <div>
            <h3 className="font-bold text-lg mb-4">{tenant?.name || "Discover AI"}</h3>
            <p className="text-gray-400 text-sm">
              Votre compagnon de voyage intelligent. Explorez, planifiez, et découvrez le monde autrement.
            </p>
          </div>
          <div>
            <h4 className="font-semibold mb-4">Navigation</h4>
            <ul className="space-y-2 text-gray-400 text-sm">
              <li><a href="/pois" className="hover:text-white">Points d&apos;intérêt</a></li>
              <li><a href="/trips" className="hover:text-white">Planifier un voyage</a></li>
              <li><a href="/chat" className="hover:text-white">Guide IA</a></li>
            </ul>
          </div>
          <div>
            <h4 className="font-semibold mb-4">Ressources</h4>
            <ul className="space-y-2 text-gray-400 text-sm">
              <li><a href="#" className="hover:text-white">API Documentation</a></li>
              <li><a href="#" className="hover:text-white">Contribuer</a></li>
              <li><a href="#" className="hover:text-white">Blog</a></li>
            </ul>
          </div>
          <div>
            <h4 className="font-semibold mb-4">Contact</h4>
            <p className="text-gray-400 text-sm">contact@discoverai.travel</p>
            <p className="text-gray-400 text-sm mt-2">Version 1.0.0</p>
          </div>
        </div>
        <div className="border-t border-gray-800 mt-8 pt-8 text-center text-gray-500 text-sm">
          © 2024 {tenant?.name || "Discover AI"}. Tous droits réservés.
        </div>
      </div>
    </footer>
  );
}
