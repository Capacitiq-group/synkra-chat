import { ref, computed } from 'vue';
import SynkraStudentVerificationAPI from 'dashboard/api/synkraStudentVerification';
import SynkraCommunityApplicationAPI from 'dashboard/api/synkraCommunityApplication';

// Shared state for the Student and Community Access cards and the plan
// cards' discounted prices. Module-level so every component sees the
// same status without fetching twice.
const student = ref(null);
const community = ref(null);

export function useSynkraProgrammes() {
  const fetchProgrammes = async () => {
    const [studentResult, communityResult] = await Promise.allSettled([
      SynkraStudentVerificationAPI.get(),
      SynkraCommunityApplicationAPI.get(),
    ]);
    if (studentResult.status === 'fulfilled') {
      student.value = studentResult.value.data;
    }
    if (communityResult.status === 'fulfilled') {
      community.value = communityResult.value.data;
    }
  };

  // Community Access (60% off) beats Student (35% off) if both apply.
  const activeProgramme = computed(() => {
    if (community.value?.verified) return 'community';
    if (student.value?.verified) return 'student';
    return null;
  });

  const activePrices = computed(() => {
    if (activeProgramme.value === 'community') {
      return community.value?.discounted_prices || null;
    }
    if (activeProgramme.value === 'student') {
      return student.value?.discounted_prices || null;
    }
    return null;
  });

  return { student, community, fetchProgrammes, activeProgramme, activePrices };
}
