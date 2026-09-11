"use client";

import { Clock, MapPin, Star, Heart } from "lucide-react";
import { useState } from "react";
import type { POI } from "@/types";

// Curated fallbacks for demo POIs if images are empty
const FALLBACK_IMAGES: Record<string, string> = {
  "casbah-dalger": "https://images.unsplash.com/photo-1596401057633-54a8fe8ef647?q=80&w=800&auto=format&fit=crop",
  "ruines-tipaza": "https://images.unsplash.com/photo-1544644181-1484b3fdfc62?q=80&w=800&auto=format&fit=crop",
  "ponts-constantine": "https://images.unsplash.com/photo-1590523741831-ab7e8b8f9c7f?q=80&w=800&auto=format&fit=crop",
  "tassili-najjer": "https://images.unsplash.com/photo-1509316975850-ff9c5deb0cd9?q=80&w=800&auto=format&fit=crop",
  "jardin-essai-hamma": "https://images.unsplash.com/photo-1585320806297-9794b3e4eeae?q=80&w=800&auto=format&fit=crop",
  "maqam-echahid": "https://images.unsplash.com/photo-1578895101407-28d8442ec5d2?q=80&w=800&auto=format&fit=crop",
  "ruines-djemila": "https://images.unsplash.com/photo-1548013146-72479768bada?q=80&w=800&auto=format&fit=crop",
};

const CATEGORY_STYLES: Record<string, { bg: string; text: string; label: string }> = {
  historical: { bg: "bg-amber-100/90", text: "text-amber-900", label: "Histoire" },
  nature: { bg: "bg-emerald-100/90", text: "text-emerald-900", label: "Nature" },
  culture: { bg: "bg-purple-100/90", text: "text-purple-900", label: "Culture" },
  adventure: { bg: "bg-orange-100/90", text: "text-orange-900", label: "Aventure" },
  desert: { bg: "bg-amber-200/90", text: "text-amber-950", label: "Désert & Sahara" },
  food: { bg: "bg-rose-100/90", text: "text-rose-900", label: "Gastronomie" },
  beaches: { bg: "bg-sky-100/90", text: "text-sky-900", label: "Plages & Mer" },
  monuments: { bg: "bg-indigo-100/90", text: "text-indigo-900", label: "Monuments" },
  crafts: { bg: "bg-violet-100/90", text: "text-violet-900", label: "Artisanat" },
  thermal: { bg: "bg-teal-100/90", text: "text-teal-900", label: "Thermalisme" },
  wellness: { bg: "bg-pink-100/90", text: "text-pink-900", label: "Détente" },
  shopping: { bg: "bg-sky-100/90", text: "text-sky-900", label: "Shopping" },
};

export function POICard({
  poi,
  onSelect,
}: {
  poi: POI;
  onSelect?: (poi: POI) => void;
}) {
  const [favorite, setFavorite] = useState(false);
  const [imageError, setImageError] = useState(false);

  const imageUrl =
    !imageError && poi.images && poi.images.length > 0 && poi.images[0]
      ? poi.images[0]
      : FALLBACK_IMAGES[poi.slug] ||
        "https://images.unsplash.com/photo-1507525428034-b723cf961d3e?q=80&w=800&auto=format&fit=crop";

  const categoriesList =
    poi.categories && poi.categories.length > 0
      ? poi.categories
      : poi.category
      ? [poi.category]
      : [];

  const rating = poi.average_rating ? poi.average_rating.toFixed(1) : "4.8";
  const reviews = poi.review_count ? `${poi.review_count} avis` : "120 avis";

  return (
    <div
      onClick={() => onSelect?.(poi)}
      className="group bg-white rounded-2xl border border-gray-100/80 overflow-hidden shadow-sm hover:shadow-card hover:-translate-y-1 transition-all duration-300 flex flex-col cursor-pointer"
    >
      {/* Image container */}
      <div className="relative h-48 w-full overflow-hidden bg-gray-100">
        <img
          src={imageUrl}
          alt={poi.name}
          onError={() => setImageError(true)}
          className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500 ease-out"
          loading="lazy"
        />
        <div className="absolute inset-0 bg-gradient-to-t from-black/40 via-transparent to-transparent opacity-60" />

        {/* Category Pills (Multi-catégories) */}
        <div className="absolute top-3 left-3 flex flex-wrap gap-1 max-w-[70%] z-10">
          {categoriesList.slice(0, 2).map((cat) => {
            const style = CATEGORY_STYLES[cat] || {
              bg: "bg-white/90",
              text: "text-gray-800",
              label: cat,
            };
            return (
              <span
                key={cat}
                className={`text-[11px] font-semibold px-2.5 py-0.5 rounded-full backdrop-blur-md shadow-xs ${style.bg} ${style.text}`}
              >
                {style.label}
              </span>
            );
          })}
          {categoriesList.length > 2 && (
            <span className="text-[10px] font-bold px-1.5 py-0.5 rounded-full bg-black/40 text-white backdrop-blur-md">
              +{categoriesList.length - 2}
            </span>
          )}
        </div>

        {/* Favorite Button */}
        <button
          type="button"
          onClick={(e) => {
            e.stopPropagation();
            setFavorite(!favorite);
          }}
          aria-label="Ajouter aux favoris"
          className="absolute top-3 right-3 w-8 h-8 rounded-full bg-white/80 hover:bg-white backdrop-blur-md flex items-center justify-center text-gray-700 hover:text-red-500 transition shadow-sm"
        >
          <Heart
            size={16}
            className={favorite ? "fill-red-500 text-red-500" : ""}
          />
        </button>

        {/* Bottom image overlay: City */}
        <div className="absolute bottom-2.5 left-3 flex items-center gap-1 text-white text-xs font-medium drop-shadow-sm">
          <MapPin size={13} className="text-accent" />
          <span>{poi.city}</span>
        </div>
      </div>

      {/* Content */}
      <div className="p-4 flex-1 flex flex-col justify-between">
        <div>
          {/* Rating and Reviews */}
          <div className="flex items-center justify-between gap-2 mb-1.5">
            <div className="flex items-center gap-1">
              <Star size={14} className="fill-accent text-accent" />
              <span className="text-xs font-bold text-ink">{rating}</span>
              <span className="text-xs text-ink-soft">({reviews})</span>
            </div>
            <div className="flex items-center gap-1 text-xs text-ink-soft">
              <Clock size={13} />
              <span>{poi.duration_minutes} min</span>
            </div>
          </div>

          <h3 className="font-bold text-base text-ink mb-1 group-hover:text-brand transition-colors line-clamp-1">
            {poi.name}
          </h3>

          <p className="text-xs text-ink-soft line-clamp-2 leading-relaxed mb-3">
            {poi.description}
          </p>
        </div>

        {/* Experiences (Niveau 3) or Tags */}
        <div className="pt-2 border-t border-gray-100 flex items-center justify-between">
          <div className="flex flex-wrap gap-1">
            {poi.experiences && poi.experiences.length > 0 ? (
              poi.experiences.slice(0, 2).map((exp: string) => (
                <span
                  key={exp}
                  className="text-[10px] bg-brand-tint/70 text-brand px-2 py-0.5 rounded-md font-semibold"
                >
                  ✨ {exp.charAt(0).toUpperCase() + exp.slice(1).replace(/_/g, ' ')}
                </span>
              ))
            ) : (
              poi.tags?.slice(0, 2).map((tag: string) => (
                <span
                  key={tag}
                  className="text-[11px] bg-canvas text-ink-soft px-2 py-0.5 rounded-md font-medium"
                >
                  #{tag}
                </span>
              ))
            )}
          </div>
          <span className="text-xs font-semibold text-brand hover:underline">
            Voir détails →
          </span>
        </div>
      </div>
    </div>
  );
}

