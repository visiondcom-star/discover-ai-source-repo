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

export interface TenantCategory {
  id: string;
  tenant_id: string;
  slug: string;
  label: string;
  parent_family?: string;
  icon_suggestion?: string;
  description?: string;
  display_order?: number;
  ai_generated?: boolean;
}

export interface POI {
  id: string;
  slug: string;
  name: string;
  description: string;
  city: string;
  category?: string;
  categories: string[];
  experiences?: string[];
  duration_minutes: number;
  price_range: string;
  latitude: number;
  longitude: number;
  tags: string[];
  images: string[];
  is_verified: boolean;
  average_rating?: number;
  review_count?: number;
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
  start_time?: string | null;
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
  full_name: string | null;
  is_admin?: boolean;
}
