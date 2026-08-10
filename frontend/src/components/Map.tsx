"use client";

import { useEffect } from "react";
import { MapContainer, TileLayer, Marker, Popup } from "react-leaflet";
import "leaflet/dist/leaflet.css";
import L from "leaflet";

// Fix default icon
const icon = L.icon({
  iconUrl: "/marker-icon.png",
  iconSize: [25, 41],
  iconAnchor: [12, 41],
});

export function Map({ pois, center = [36.7, 3.0], zoom = 6 }: { 
  pois: any[]; 
  center?: [number, number]; 
  zoom?: number;
}) {
  useEffect(() => {
    // Fix Leaflet default marker icon in Next.js
    delete (L.Icon.Default.prototype as any)._getIconUrl;
    L.Icon.Default.mergeOptions({
      iconRetinaUrl: "https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon-2x.png",
      iconUrl: "https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png",
      shadowUrl: "https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png",
    });
  }, []);

  return (
    <MapContainer center={center} zoom={zoom} className="h-full w-full">
      <TileLayer
        attribution='&copy; <a href="https://carto.com/">CARTO</a>'
        url="https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png"
      />
      {pois.filter(p => p.latitude && p.longitude).map((poi) => (
        <Marker key={poi.id} position={[poi.latitude, poi.longitude]} icon={icon}>
          <Popup>
            <div className="p-2">
              <h3 className="font-bold">{poi.name}</h3>
              <p className="text-sm text-gray-600">{poi.city}</p>
              <p className="text-sm">{poi.category}</p>
              <a href={`/pois/${poi.id}`} className="text-primary text-sm hover:underline">
                Voir détails
              </a>
            </div>
          </Popup>
        </Marker>
      ))}
    </MapContainer>
  );
}
