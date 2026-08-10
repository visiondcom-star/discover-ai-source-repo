export interface Tenant {
  id: string;
  slug: string;
  name: string;
  default_language: string;
  supported_languages: string[];
  default_currency: string;
  primary_color: string;
  secondary_color: string;
}

export interface POI {
  id: string;
  slug: string;
  name: string;
  description: string;
  city: string;
  category: string;
  duration_minutes: number;
  price_range: string;
  latitude: number;
  longitude: number;
  tags: string[];
  images: string[];
  is_verified: boolean;
}

export interface Trip {
  id: string;
  title: string;
  description: string;
  num_days: number;
  budget_level: string;
  travel_style: string;
  status: string;
  items: TripItem[];
}

export interface TripItem {
  id: string;
  poi_id: string;
  day_number: number;
  order_index: number;
  poi?: POI;
  notes: string;
}

export interface ChatMessage {
  role: "user" | "assistant";
  content: string;
}

export interface User {
  id: string;
  email: string;
  full_name: string;
}
