import { EmergencyRequestRepository } from '../repositories/emergency-request.repository';
import {
  UserRepository,
  ResponderAvailability,
} from '../repositories/user.repository';

type AssignmentOutcome = {
  emergency: any;
  assignedResponder: any | null;
  distanceKm: number | null;
};

export class AssignmentService {
  /**
   * Attempt to auto-assign the closest available responder to a pending request.
   */
  static assignClosestResponder(
    emergencyId: string,
    excludedResponderIds: string[] = [],
  ): AssignmentOutcome {
    const emergency = EmergencyRequestRepository.findById(emergencyId);
    if (!emergency) {
      throw new Error('Emergency request not found');
    }

    if (emergency.status !== 'pending') {
      return {
        emergency,
        assignedResponder: null,
        distanceKm: null,
      };
    }

    const responders = UserRepository.findAssignableResponders(excludedResponderIds);
    if (responders.length === 0) {
      return {
        emergency,
        assignedResponder: null,
        distanceKm: null,
      };
    }

    const ranked = responders
      .map((responder) => {
        const distanceKm = this.haversineKm(
          Number(emergency.latitude),
          Number(emergency.longitude),
          Number(responder.last_latitude),
          Number(responder.last_longitude),
        );

        const workloadPenaltyKm = Number(responder.active_assignments ?? 0) * 3;

        return {
          responder,
          distanceKm,
          score: distanceKm + workloadPenaltyKm,
        };
      })
      .sort((a, b) => a.score - b.score);

    const best = ranked[0];
    const assigned = EmergencyRequestRepository.assignResponder(
      emergencyId,
      best.responder.id,
      best.responder.phone,
    );

    if (!assigned) {
      return {
        emergency: EmergencyRequestRepository.findById(emergencyId),
        assignedResponder: null,
        distanceKm: null,
      };
    }

    UserRepository.updateResponderAvailability(
      best.responder.id,
      'busy',
      Number(best.responder.last_latitude),
      Number(best.responder.last_longitude),
    );

    return {
      emergency: assigned,
      assignedResponder: best.responder,
      distanceKm: Number(best.distanceKm.toFixed(2)),
    };
  }

  /**
   * Reassign a request after decline by excluding specified responders.
   */
  static reassignAfterDecline(
    emergencyId: string,
    excludedResponderIds: string[],
  ): AssignmentOutcome {
    return this.assignClosestResponder(emergencyId, excludedResponderIds);
  }

  static setResponderAvailability(
    responderId: string,
    availability: ResponderAvailability,
    latitude?: number,
    longitude?: number,
  ): any {
    return UserRepository.updateResponderAvailability(
      responderId,
      availability,
      latitude,
      longitude,
    );
  }

  private static haversineKm(
    lat1: number,
    lng1: number,
    lat2: number,
    lng2: number,
  ): number {
    const toRad = (value: number) => (value * Math.PI) / 180;
    const earthRadiusKm = 6371;

    const dLat = toRad(lat2 - lat1);
    const dLng = toRad(lng2 - lng1);

    const a =
      Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(toRad(lat1)) *
        Math.cos(toRad(lat2)) *
        Math.sin(dLng / 2) *
        Math.sin(dLng / 2);

    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return earthRadiusKm * c;
  }
}
