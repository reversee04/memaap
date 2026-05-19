import db from '../config/database';
import { v4 as uuidv4 } from 'uuid';

export class HospitalRepository {
  /** Get all available hospitals. */
  static findAll(): any[] {
    return db.prepare(
      'SELECT * FROM hospitals WHERE is_available = 1 ORDER BY name'
    ).all();
  }

  /** Get hospitals within a bounding box approximation (fast, no trig). */
  static findNearby(lat: number, lng: number, radiusKm: number = 10): any[] {
    // 1 degree lat ≈ 111 km
    const latDelta = radiusKm / 111;
    const lngDelta = radiusKm / (111 * Math.cos((lat * Math.PI) / 180));

    return db.prepare(`
      SELECT * FROM hospitals
      WHERE is_available = 1
        AND latitude  BETWEEN ? AND ?
        AND longitude BETWEEN ? AND ?
      ORDER BY
        ((latitude - ?) * (latitude - ?) + (longitude - ?) * (longitude - ?))
    `).all(
      lat - latDelta, lat + latDelta,
      lng - lngDelta, lng + lngDelta,
      lat, lat, lng, lng,
    );
  }

  /** Get a single hospital by ID. */
  static findById(id: string): any {
    return db.prepare('SELECT * FROM hospitals WHERE id = ?').get(id);
  }

  /** Insert a new hospital. */
  static create(data: {
    name: string; address: string; latitude: number; longitude: number;
    phone: string; email?: string; website?: string;
    emergencyServices?: string[]; isAvailable?: boolean;
  }): any {
    const id = uuidv4();
    db.prepare(`
      INSERT INTO hospitals
        (id, name, address, latitude, longitude, phone, email, website,
         emergency_services, is_available, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'), datetime('now'))
    `).run(
      id,
      data.name, data.address, data.latitude, data.longitude, data.phone,
      data.email || null, data.website || null,
      JSON.stringify(data.emergencyServices || []),
      data.isAvailable !== false ? 1 : 0,
    );
    return this.findById(id);
  }

  /** Update availability status. */
  static updateAvailability(id: string, isAvailable: boolean): void {
    db.prepare(
      "UPDATE hospitals SET is_available = ?, updated_at = datetime('now') WHERE id = ?"
    ).run(isAvailable ? 1 : 0, id);
  }

  /** Simple text search by name. */
  static search(query: string): any[] {
    return db.prepare(
      "SELECT * FROM hospitals WHERE name LIKE ? OR address LIKE ? ORDER BY name"
    ).all(`%${query}%`, `%${query}%`);
  }
}
