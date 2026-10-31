import type { MarketplacePaymentProvider } from "./payment-provider.ts";

const providers = new Map<string, MarketplacePaymentProvider>();

export function registerPaymentProvider(code: string, adapter: MarketplacePaymentProvider): void {
  if (!/^[a-z0-9_-]{2,40}$/u.test(code)) throw new Error("invalid_provider_code");
  if (providers.has(code)) throw new Error(`provider_already_registered:${code}`);
  providers.set(code, adapter);
}

export function getPaymentProvider(code: string | null | undefined): MarketplacePaymentProvider {
  if (!code) throw new Error("payment_provider_not_configured");
  const adapter = providers.get(code);
  if (!adapter) throw new Error(`payment_provider_adapter_not_implemented:${code}`);
  return adapter;
}

// Deliberately no Razorpay/Cashfree implementation is registered here.
// Add a provider adapter only after written ShelfShare marketplace approval,
// exact product approval, sandbox validation and legal/accounting sign-off.
