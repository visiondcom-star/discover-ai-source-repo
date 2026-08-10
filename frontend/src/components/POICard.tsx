"use client";

import { Clock, MapPin, Tag } from "lucide-react";

export function POICard({ poi }: { poi: any }) {
  const categoryColors: Record<string, string> = {
    historical: "bg-amber-100 text-amber-800",
    nature: "bg-green-100 text-green-800",
    culture: "bg-purple-100 text-purple-800",
    adventure: "bg-orange-100 text-orange-800",
    food: "bg-red-100 text-red-800",
    shopping: "bg-blue-100 text-blue-800",
  };

  return (
    <div className="bg-white rounded-xl shadow-sm border overflow-hidden hover:shadow-md transition">
      <div className="h-48 bg-gray-200 flex items-center justify-center">
        <MapPin className="w-12 h-12 text-gray-400" />
      </div>
      <div className="p-4">
        <div className="flex items-center gap-2 mb-2">
          <span className={`text-xs font-medium px-2 py-1 rounded-full ${categoryColors[poi.category] || "bg-gray-100"}`}>
            {poi.category}
          </span>
        </div>
        <h3 className="font-bold text-lg mb-1">{poi.name}</h3>
        <p className="text-gray-600 text-sm mb-3 line-clamp-2">{poi.description}</p>
        <div className="flex items-center gap-4 text-sm text-gray-500">
          <span className="flex items-center gap-1">
            <MapPin size={14} />
            {poi.city}
          </span>
          <span className="flex items-center gap-1">
            <Clock size={14} />
            {poi.duration_minutes} min
          </span>
        </div>
        {poi.tags && poi.tags.length > 0 && (
          <div className="flex flex-wrap gap-1 mt-3">
            {poi.tags.slice(0, 3).map((tag: string) => (
              <span key={tag} className="text-xs bg-gray-100 text-gray-600 px-2 py-0.5 rounded">
                {tag}
              </span>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
