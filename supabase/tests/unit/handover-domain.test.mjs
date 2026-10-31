import test from "node:test";
import assert from "node:assert/strict";
import { mayCompleteHandover } from "../../functions/_shared/domain.ts";

const valid = {
  now: 1000,
  expiresAt: 2000,
  tokenConsumed: true,
  ownerConfirmed: true,
  readerConfirmed: true,
  ownerConditionConfirmed: true,
  readerConditionConfirmed: true,
  ownerPhotoCount: 1,
  readerPhotoCount: 1,
};

test("handover completes only after token use, both independent confirmations and photos", () => {
  assert.equal(mayCompleteHandover(valid), true);
  assert.equal(mayCompleteHandover({ ...valid, readerConfirmed: false }), false);
  assert.equal(mayCompleteHandover({ ...valid, ownerConditionConfirmed: false }), false);
  assert.equal(mayCompleteHandover({ ...valid, readerPhotoCount: 0 }), false);
  assert.equal(mayCompleteHandover({ ...valid, tokenConsumed: false }), false);
});

test("expired handover token cannot complete a session", () => {
  assert.equal(mayCompleteHandover({ ...valid, now: 2000 }), false);
});
