"use client";

import { Clock, MapPin } from "lucide-react";

export function TripTimeline({ items }: { items: any[] }) {
  const grouped = items.reduce((acc: any, item: any) => {
    const day = item.day_number;
    if (!acc[day]) acc[day] = [];
    acc[day].push(item);
    return acc;
  }, {});

  return (
    <div className="space-y-8">
      {Object.entries(grouped).map(([day, dayItems]: [string, any]) => (
        <div key={day} className="bg-white rounded-xl border p-6">
          <h3 className="text-lg font-bold mb-4 flex items-center gap-2">
            <span className="w-8 h-8 rounded-full bg-primary text-white flex items-center justify-center text-sm">
              {day}
            </span>
            Jour {day}
          </h3>
          <div className="space-y-4">
            {dayItems.map((item: any, idx: number) => (
              <div key={idx} className="flex gap-4">
                <div className="w-16 text-sm text-gray-500 font-medium">
                  {item.start_time ? new Date(item.start_time).toLocaleTimeString("fr-FR", {hour: "2-digit", minute: "2-digit"}) : "--:--"}
                </div>
                <div className="flex-1 pb-4 border-l-2 border-gray-200 pl-4 relative">
                  <div className="absolute -left-[5px] top-1 w-2 h-2 rounded-full bg-primary"></div>
                  <h4 className="font-semibold">{item.poi?.name || "Point d'intérêt"}</h4>
                  <p className="text-sm text-gray-600 flex items-center gap-1 mt-1">
                    <MapPin size={14} />
                    {item.poi?.city}
                  </p>
                  <p className="text-sm text-gray-500 flex items-center gap-1 mt-1">
                    <Clock size={14} />
                    {item.poi?.duration_minutes} min
                  </p>
                  {item.notes && (
                    <p className="text-sm text-gray-500 mt-2 italic">{item.notes}</p>
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
