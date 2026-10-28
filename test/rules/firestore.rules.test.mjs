import { readFileSync } from 'node:fs';
import { after, afterEach, before, describe, it } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { doc, serverTimestamp, setDoc, Timestamp, updateDoc } from 'firebase/firestore';

let env;

// `firebase emulators:exec` exports FIRESTORE_EMULATOR_HOST; fall back to the
// port declared in firebase.json.
const [emuHost, emuPort] = (process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8085').split(':');

const baseUser = (overrides = {}) => ({
  fullName: 'Amel Ben Salah',
  email: 'amel@esprit.tn',
  role: 'student',
  isVerifiedStudent: false,
  isPhoneVerified: false,
  ratingAverage: 0,
  ratingCount: 0,
  createdAt: new Date('2024-09-01'),
  campus: 'ESPRIT Ghazela',
  disabled: false,
  studentCard: { status: 'none' },
  ...overrides,
});

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'campusconnect-esprit',
    firestore: {
      rules: readFileSync('../../firestore.rules', 'utf8'),
      host: emuHost,
      port: Number(emuPort),
    },
  });
});

after(async () => {
  await env.cleanup();
});

afterEach(async () => {
  await env.clearFirestore();
});

async function seed() {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users/alice'), baseUser());
    await setDoc(doc(db, 'users/admin1'), baseUser({ fullName: 'Admin', role: 'admin' }));
  });
}

describe('users rules', () => {
  it('owner cannot set studentCard.status to verified', async () => {
    await seed();
    const db = env.authenticatedContext('alice').firestore();
    await assertFails(updateDoc(doc(db, 'users/alice'), { studentCard: { status: 'verified' } }));
  });

  it('owner can submit a student card as pending with imagePath and submittedAt', async () => {
    await seed();
    const db = env.authenticatedContext('alice').firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'users/alice'), {
        studentCard: {
          status: 'pending',
          imagePath: 'student_cards/alice/card.jpg',
          submittedAt: serverTimestamp(),
        },
      }),
    );
  });

  it('owner cannot add reviewedBy while submitting', async () => {
    await seed();
    const db = env.authenticatedContext('alice').firestore();
    await assertFails(
      updateDoc(doc(db, 'users/alice'), {
        studentCard: { status: 'pending', imagePath: 'x.jpg', reviewedBy: 'alice' },
      }),
    );
  });

  it('owner cannot set disabled', async () => {
    await seed();
    const db = env.authenticatedContext('alice').firestore();
    await assertFails(updateDoc(doc(db, 'users/alice'), { disabled: true }));
  });

  it('admin can set verified and isVerifiedStudent', async () => {
    await seed();
    const db = env.authenticatedContext('admin1').firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'users/alice'), {
        studentCard: { status: 'verified', reviewedBy: 'admin1' },
        isVerifiedStudent: true,
      }),
    );
  });

  it('create with disabled: true is denied', async () => {
    const db = env.authenticatedContext('bob').firestore();
    await assertFails(setDoc(doc(db, 'users/bob'), baseUser({ disabled: true })));
  });

  it('create with defaults is allowed', async () => {
    const db = env.authenticatedContext('bob').firestore();
    await assertSucceeds(setDoc(doc(db, 'users/bob'), baseUser()));
  });

  it('create with a non-none studentCard is denied', async () => {
    const db = env.authenticatedContext('bob').firestore();
    await assertFails(
      setDoc(doc(db, 'users/bob'), baseUser({ studentCard: { status: 'verified' } })),
    );
  });

  it('owner can still update fullName', async () => {
    await seed();
    const db = env.authenticatedContext('alice').firestore();
    await assertSucceeds(updateDoc(doc(db, 'users/alice'), { fullName: 'Amel B.' }));
  });

  // Real client payload of AppUser.toEditableMap() (no studentCard).
  const profileEdit = {
    fullName: 'Amel B.',
    major: 'GL',
    year: '3ème année',
    photoUrl: null,
    skills: ['Flutter'],
    twoFactorEnabled: false,
    campus: 'ESPRIT Ghazela',
    studentId: '12345',
  };

  const cards = {
    rejected: {
      status: 'rejected',
      imagePath: 'student_cards/alice/card.jpg',
      submittedAt: Timestamp.now(),
      reviewedBy: 'admin1',
      reviewedAt: Timestamp.now(),
      rejectReason: 'Illisible',
    },
    verified: {
      status: 'verified',
      imagePath: 'student_cards/alice/card.jpg',
      submittedAt: Timestamp.now(),
      reviewedBy: 'admin1',
      reviewedAt: Timestamp.now(),
    },
    pending: {
      status: 'pending',
      imagePath: 'student_cards/alice/card.jpg',
      submittedAt: Timestamp.now(),
    },
  };

  async function seedAlice(extra, drop) {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const data = baseUser(extra);
      if (drop) delete data[drop];
      const db = ctx.firestore();
      await setDoc(doc(db, 'users/alice'), data);
      await setDoc(doc(db, 'users/admin1'), baseUser({ role: 'admin' }));
    });
  }

  it('profile edit merge succeeds for a legacy user with no studentCard field', async () => {
    await seedAlice({}, 'studentCard');
    const db = env.authenticatedContext('alice').firestore();
    await assertSucceeds(setDoc(doc(db, 'users/alice'), profileEdit, { merge: true }));
  });

  for (const [name, card] of Object.entries(cards)) {
    it(`profile edit merge succeeds for a user with a ${name} card`, async () => {
      await seedAlice({ studentCard: card });
      const db = env.authenticatedContext('alice').firestore();
      await assertSucceeds(setDoc(doc(db, 'users/alice'), profileEdit, { merge: true }));
    });
  }

  it('owner can resubmit a card as pending after a rejection', async () => {
    await seedAlice({ studentCard: cards.rejected });
    const db = env.authenticatedContext('alice').firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'users/alice'), {
        studentCard: {
          status: 'pending',
          imagePath: 'student_cards/alice/new.jpg',
          submittedAt: serverTimestamp(),
        },
      }),
    );
  });

  it('owner cannot write studentCard status none against a missing field', async () => {
    await seedAlice({}, 'studentCard');
    const db = env.authenticatedContext('alice').firestore();
    await assertFails(updateDoc(doc(db, 'users/alice'), { studentCard: { status: 'none' } }));
  });

  it('admin can reject a card with reason and reviewer fields', async () => {
    await seedAlice({ studentCard: cards.pending });
    const db = env.authenticatedContext('admin1').firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'users/alice'), {
        studentCard: {
          status: 'rejected',
          imagePath: 'student_cards/alice/card.jpg',
          submittedAt: Timestamp.now(),
          rejectReason: 'Illisible',
          reviewedBy: 'admin1',
          reviewedAt: serverTimestamp(),
        },
        isVerifiedStudent: false,
      }),
    );
  });
});
