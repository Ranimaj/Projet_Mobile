import { readFileSync } from 'node:fs';
import { after, afterEach, before, describe, it } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  addDoc,
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
  where,
} from 'firebase/firestore';

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
        studentCard: {
          status: 'pending',
          imagePath: 'student_cards/alice/x.jpg',
          submittedAt: serverTimestamp(),
          reviewedBy: 'alice',
        },
      }),
    );
  });

  it('owner cannot point a submission at another user\'s card', async () => {
    await seed();
    const db = env.authenticatedContext('alice').firestore();
    await assertFails(
      updateDoc(doc(db, 'users/alice'), {
        studentCard: {
          status: 'pending',
          imagePath: 'student_cards/bob/card.jpg',
          submittedAt: serverTimestamp(),
        },
      }),
    );
  });

  it('owner cannot use a look-alike prefix for another user', async () => {
    await seed();
    const db = env.authenticatedContext('alice').firestore();
    await assertFails(
      updateDoc(doc(db, 'users/alice'), {
        studentCard: {
          status: 'pending',
          imagePath: 'student_cards/alice2/card.jpg',
          submittedAt: serverTimestamp(),
        },
      }),
    );
  });

  it('owner cannot submit without submittedAt', async () => {
    await seed();
    const db = env.authenticatedContext('alice').firestore();
    await assertFails(
      updateDoc(doc(db, 'users/alice'), {
        studentCard: { status: 'pending', imagePath: 'student_cards/alice/card.jpg' },
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

// --- Vente & Don ---------------------------------------------------------------

const baseArticle = (overrides = {}) => ({
  ownerId: 'alice',
  ownerName: 'Amel Ben Salah',
  title: 'Calculatrice TI-83',
  description: 'Très bon état, avec piles.',
  price: 40,
  category: 'Électronique',
  imageUrls: [],
  status: 'available',
  latitude: null,
  longitude: null,
  createdAt: new Date('2026-11-01'),
  viewCount: 3,
  favoritedBy: [],
  ...overrides,
});

async function seedArticle(overrides = {}) {
  await seed();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users/bob'), baseUser({ fullName: 'Bob' }));
    await setDoc(doc(db, 'articles/a1'), baseArticle(overrides));
  });
}

describe('articles rules', () => {
  it('a visitor can read articles', async () => {
    await seedArticle();
    const db = env.unauthenticatedContext().firestore();
    await assertSucceeds(getDoc(doc(db, 'articles/a1')));
  });

  it('owner can create a valid article', async () => {
    await seed();
    const db = env.authenticatedContext('alice').firestore();
    await assertSucceeds(setDoc(doc(db, 'articles/new'), baseArticle()));
  });

  it('cannot create an article for someone else', async () => {
    await seed();
    const db = env.authenticatedContext('bob').firestore();
    await assertFails(setDoc(doc(db, 'articles/new'), baseArticle()));
  });

  it('cannot create an article with a negative price or 7 photos', async () => {
    await seed();
    const db = env.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(db, 'articles/n1'), baseArticle({ price: -5 })));
    await assertFails(
      setDoc(doc(db, 'articles/n2'), baseArticle({ imageUrls: ['1', '2', '3', '4', '5', '6', '7'] })),
    );
  });

  it('owner can edit title, price and status', async () => {
    await seedArticle();
    const db = env.authenticatedContext('alice').firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'articles/a1'), { title: 'TI-83 Plus', price: 35, status: 'reserved' }),
    );
  });

  it('owner cannot give the article to another owner', async () => {
    await seedArticle();
    const db = env.authenticatedContext('alice').firestore();
    await assertFails(updateDoc(doc(db, 'articles/a1'), { ownerId: 'bob' }));
  });

  it('another user cannot edit the title', async () => {
    await seedArticle();
    const db = env.authenticatedContext('bob').firestore();
    await assertFails(updateDoc(doc(db, 'articles/a1'), { title: 'Volé' }));
  });

  it('another user can add and remove their own favorite', async () => {
    await seedArticle({ favoritedBy: ['carol'] });
    const db = env.authenticatedContext('bob').firestore();
    await assertSucceeds(updateDoc(doc(db, 'articles/a1'), { favoritedBy: ['carol', 'bob'] }));
    await assertSucceeds(updateDoc(doc(db, 'articles/a1'), { favoritedBy: ['carol'] }));
  });

  it('another user cannot remove someone else\'s favorite', async () => {
    await seedArticle({ favoritedBy: ['carol'] });
    const db = env.authenticatedContext('bob').firestore();
    await assertFails(updateDoc(doc(db, 'articles/a1'), { favoritedBy: [] }));
  });

  it('a view adds exactly one to viewCount', async () => {
    await seedArticle({ viewCount: 3 });
    const db = env.authenticatedContext('bob').firestore();
    await assertSucceeds(updateDoc(doc(db, 'articles/a1'), { viewCount: 4 }));
    await assertFails(updateDoc(doc(db, 'articles/a1'), { viewCount: 100 }));
  });

  it('only the owner can delete', async () => {
    await seedArticle();
    await assertFails(deleteDoc(doc(env.authenticatedContext('bob').firestore(), 'articles/a1')));
    await assertSucceeds(deleteDoc(doc(env.authenticatedContext('alice').firestore(), 'articles/a1')));
  });
});

const baseConversation = (overrides = {}) => ({
  articleId: 'a1',
  articleTitle: 'Calculatrice TI-83',
  articleImageUrl: null,
  sellerId: 'alice',
  buyerId: 'bob',
  names: { alice: 'Amel', bob: 'Bob' },
  participants: ['bob', 'alice'],
  lastMessage: '',
  lastSenderId: null,
  updatedAt: new Date('2026-11-05'),
  unreadBy: [],
  ...overrides,
});

async function seedConversation() {
  await seedArticle();
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'conversations/a1_bob'), baseConversation());
  });
}

describe('conversations rules', () => {
  it('a buyer can check for and create the conversation', async () => {
    await seedArticle();
    const db = env.authenticatedContext('bob').firestore();
    await assertSucceeds(getDoc(doc(db, 'conversations/a1_bob')));
    await assertSucceeds(setDoc(doc(db, 'conversations/a1_bob'), baseConversation()));
  });

  it('cannot create a conversation in someone else\'s name', async () => {
    await seedArticle();
    const db = env.authenticatedContext('carol').firestore();
    await assertFails(setDoc(doc(db, 'conversations/a1_bob'), baseConversation()));
  });

  it('only participants can read the conversation and its messages', async () => {
    await seedConversation();
    const carol = env.authenticatedContext('carol').firestore();
    await assertFails(getDoc(doc(carol, 'conversations/a1_bob')));
    await assertFails(getDocs(collection(carol, 'conversations/a1_bob/messages')));
    const alice = env.authenticatedContext('alice').firestore();
    await assertSucceeds(getDoc(doc(alice, 'conversations/a1_bob')));
    await assertSucceeds(
      getDocs(query(collection(alice, 'conversations'), where('participants', 'array-contains', 'alice'))),
    );
  });

  it('participants can send messages as themselves only', async () => {
    await seedConversation();
    const bob = env.authenticatedContext('bob').firestore();
    await assertSucceeds(
      addDoc(collection(bob, 'conversations/a1_bob/messages'), {
        senderId: 'bob',
        text: 'Bonjour, toujours dispo ?',
        sentAt: serverTimestamp(),
      }),
    );
    await assertFails(
      addDoc(collection(bob, 'conversations/a1_bob/messages'), {
        senderId: 'alice',
        text: 'Usurpation',
        sentAt: serverTimestamp(),
      }),
    );
    const carol = env.authenticatedContext('carol').firestore();
    await assertFails(
      addDoc(collection(carol, 'conversations/a1_bob/messages'), {
        senderId: 'carol',
        text: 'Intrus',
        sentAt: serverTimestamp(),
      }),
    );
  });

  it('participants can update the header but not the participants', async () => {
    await seedConversation();
    const alice = env.authenticatedContext('alice').firestore();
    await assertSucceeds(
      updateDoc(doc(alice, 'conversations/a1_bob'), { lastMessage: 'Oui !', unreadBy: ['bob'] }),
    );
    await assertFails(
      updateDoc(doc(alice, 'conversations/a1_bob'), { participants: ['alice', 'carol'] }),
    );
  });
});

describe('devices & logins rules', () => {
  const device = (overrides = {}) => ({
    name: 'Pixel 8',
    platform: 'android',
    location: 'Tunis, Tunisie',
    trusted: true,
    revoked: false,
    signedOut: false,
    alertPending: false,
    ...overrides,
  });

  it('only the owner writes their devices; admins can read them', async () => {
    await seed();
    const alice = env.authenticatedContext('alice').firestore();
    await assertSucceeds(setDoc(doc(alice, 'users/alice/devices/d1'), device()));
    await assertSucceeds(updateDoc(doc(alice, 'users/alice/devices/d1'), { revoked: true }));
    await assertFails(setDoc(doc(alice, 'users/alice/devices/d2'), device({ trusted: 'yes' })));

    const bob = env.authenticatedContext('bob').firestore();
    await assertFails(getDoc(doc(bob, 'users/alice/devices/d1')));
    await assertFails(updateDoc(doc(bob, 'users/alice/devices/d1'), { revoked: true }));

    const admin = env.authenticatedContext('admin1').firestore();
    await assertSucceeds(getDoc(doc(admin, 'users/alice/devices/d1')));
  });

  it('logins are append-only, at server time', async () => {
    await seed();
    const alice = env.authenticatedContext('alice').firestore();
    const login = { deviceId: 'd1', deviceName: 'Pixel 8', location: null, newDevice: true };
    const ref = await assertSucceeds(
      addDoc(collection(alice, 'users/alice/logins'), { ...login, at: serverTimestamp() }),
    );
    await assertFails(
      addDoc(collection(alice, 'users/alice/logins'), { ...login, at: Timestamp.fromDate(new Date('2020-01-01')) }),
    );
    await assertFails(updateDoc(ref, { deviceName: 'Autre' }));
    const bob = env.authenticatedContext('bob').firestore();
    await assertFails(addDoc(collection(bob, 'users/alice/logins'), { ...login, at: serverTimestamp() }));
  });
});

describe('reports & reportCount rules', () => {
  const report = (overrides = {}) => ({
    reporterId: 'bob',
    reporterName: 'Bob',
    targetId: 'alice',
    targetName: 'Alice',
    reason: 'scam',
    details: 'Demande un virement.',
    status: 'pending',
    createdAt: serverTimestamp(),
    ...overrides,
  });

  it('a student reports another account once, under their own id', async () => {
    await seed();
    const bob = env.authenticatedContext('bob').firestore();
    await assertSucceeds(setDoc(doc(bob, 'reports/bob_alice'), report()));
    await assertSucceeds(getDoc(doc(bob, 'reports/bob_alice')));
    await assertFails(setDoc(doc(bob, 'reports/bob_alice'), report({ reason: 'other' })));
    await assertFails(setDoc(doc(bob, 'reports/carol_alice'), report({ reporterId: 'carol' })));
    await assertFails(setDoc(doc(bob, 'reports/bob_bob'), report({ targetId: 'bob' })));
    await assertFails(setDoc(doc(bob, 'reports/bob_x'), report({ targetId: 'x', status: 'confirmed' })));
    await assertFails(getDocs(collection(bob, 'reports')));
  });

  it('only admins confirm reports and change reportCount', async () => {
    await seed();
    const bob = env.authenticatedContext('bob').firestore();
    await setDoc(doc(bob, 'reports/bob_alice'), report());
    await assertFails(updateDoc(doc(bob, 'reports/bob_alice'), { status: 'dismissed' }));

    const alice = env.authenticatedContext('alice').firestore();
    await assertFails(updateDoc(doc(alice, 'users/alice'), { reportCount: 0 }));

    const admin = env.authenticatedContext('admin1').firestore();
    await assertSucceeds(getDocs(collection(admin, 'reports')));
    await assertSucceeds(
      updateDoc(doc(admin, 'reports/bob_alice'), { status: 'confirmed', reviewedBy: 'admin1', reviewedAt: serverTimestamp() }),
    );
    await assertSucceeds(updateDoc(doc(admin, 'users/alice'), { reportCount: 1 }));
    await assertFails(updateDoc(doc(admin, 'reports/bob_alice'), { status: 'dismissed' }));
  });

  it('a new profile cannot start with reports set', async () => {
    const carol = env.authenticatedContext('carol').firestore();
    await assertFails(setDoc(doc(carol, 'users/carol'), baseUser({ reportCount: -3 })));
    await assertSucceeds(setDoc(doc(carol, 'users/carol'), baseUser({ reportCount: 0 })));
  });
});
