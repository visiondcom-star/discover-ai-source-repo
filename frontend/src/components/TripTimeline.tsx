"use client";

import { Clock, MapPin } from "lucide-react";
import type { TripItem } from "@/types";

export function TripTimeline({ items }: { items: TripItem[] }) {
  const grouped = items.reduce<Record<number, TripItem[]>>((acc, item) => {
    const day = item.day_number;
    if (!acc[day]) acc[day] = [];
    acc[day].push(item);
    return acc;
  }, {});

  return (
    <div className="space-y-8">
      {Object.entries(grouped).map(([day, dayItems]) => (
        <div key={day} className="bg-white rounded-[24px] border border-gray-100 shadow-card p-6">
          <h3 className="font-display text-lg font-semibold mb-6 flex items-center gap-3">
            <span className="w-9 h-9 rounded-full bg-accent/20 border border-accent text-brand font-bold flex items-center justify-center text-sm shadow-xs">
              {day}
            </span>
            <span>Jour {day}</span>
          </h3>
          <div className="relative pl-6 space-y-6 before:absolute before:left-[17px] before:top-2 before:bottom-2 before:w-0.5 before:bg-brand/20">
            {dayItems.map((item, idx) => (
              <div key={idx} className="relative flex gap-4">
                <div className="absolute -left-[30px] top-1.5 w-3 h-3 rounded-full bg-brand ring-4 ring-white shadow-xs" />
                <div className="w-16 text-sm text-ink-soft font-medium pt-0.5">
                  {item.start_time ? new Date(item.start_time).toLocaleTimeString("fr-FR", {hour: "2-digit", minute: "2-digit"}) : "--:--"}
                </div>
                <div className="flex-1 pb-4">
                  <h4 className="font-display font-semibold text-base text-ink">{item.poi?.name || "Point d'intérêt"}</h4>
                  <p className="text-sm text-ink-soft flex items-center gap-1 mt-1">
                    <MapPin size={14} strokeWidth={1.75} className="text-accent" />
                    <span>{item.poi?.city}</span>
                  </p>
                  <p className="text-sm text-ink-soft flex items-center gap-1 mt-1">
                    <Clock size={14} strokeWidth={1.75} />
                    <span>{item.poi?.duration_minutes} min</span>
                  </p>
                  {item.notes && (
                    <p className="text-sm text-ink-soft mt-2 italic">{item.notes}</p>
                  )}
                </div>
              </div>
            ))}
          </div>
        </div>
      ))}
    </div>
  );
}
