/* ═══════════════════════════════════════════════════════════════════
   Test de régression — COMMANDE FANTÔME du portail B2B (recette #177).
   Scénario du constat : un panier persisté + une restauration de session
   ne doivent JAMAIS déclencher place_order sans clic utilisateur.

   Lancer depuis la racine du dépôt (playwright dans node_modules) :
     node tests/recette-portail-phantom.js
   Sortie : PASS/FAIL par assertion, code de sortie 1 si échec.

   Le RPC est stubbé (compteur) — aucun appel réseau vers Supabase.
   ═══════════════════════════════════════════════════════════════════ */
const path = require('path');
const { chromium } = require(path.join(__dirname, '..', 'node_modules', 'playwright'));

const PORTAIL = 'file:///' + path.join(__dirname, '..', 'portail.html').replace(/\\/g, '/');

let failures = 0;
function check(name, cond, detail) {
  console.log((cond ? 'PASS' : 'FAIL') + ' - ' + name + (detail !== undefined ? ' [' + detail + ']' : ''));
  if (!cond) failures++;
}

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 380, height: 780 } });
  const pageErrors = [];
  page.on('pageerror', e => pageErrors.push(e.message));

  await page.goto(PORTAIL, { waitUntil: 'load' });
  await page.waitForTimeout(1200);

  // ── Mise en place : panier persisté + session cliente simulée + stubs ──
  await page.evaluate(() => {
    window.__rpcCount = 0;
    // Stubs par affectation de PROPRIÉTÉ (sb est const) — zéro réseau.
    sb.rpc = async (fn) => { window.__rpcCount++; return { data: 'cmd-regression', error: null }; };
    sb.auth.signOut = async () => ({ error: null });
    sb.from = (t) => {
      const b = {};
      ['select', 'gte', 'lt', 'not', 'order', 'limit', 'eq', 'is', 'in'].forEach(m => { b[m] = () => b; });
      b.then = (res) => Promise.resolve({ data: [], error: null }).then(res);
      return b;
    };
    catalogue = [{ produit_id: 'poulet_entier', nom: 'Poulet entier', calibre: '1100g',
      unite: 'unite', prix_kg_fcfa: 2400, description: '', image_url: null }];
    // Panier persisté NON VIDE (l'état du constat de recette).
    cart = [{ produit_id: 'poulet_entier', nom: 'Poulet entier', unite: 'unite',
      prix_kg_fcfa: 2400, quantite_kg: 2 }];
    saveCart();
  });

  // ── 1. RESTAURATION DE SESSION (le chemin exact d'un reload avec session
  //       persistée : enterApp) — puis tous les événements suspects. ──
  await page.evaluate(async () => {
    document.getElementById('screen-login').classList.add('hidden');
    await enterApp(); // loadCart + updateCartBadge + switchView('catalogue')
    // Événements que le constat suspectait de déclencher une soumission :
    document.dispatchEvent(new Event('visibilitychange'));
    window.dispatchEvent(new Event('online'));
    window.dispatchEvent(new Event('offline'));
    window.dispatchEvent(new Event('online'));
    window.dispatchEvent(new StorageEvent('storage', { key: 'coqorico_portail_cart_v1' }));
    window.dispatchEvent(new Event('focus'));
    document.dispatchEvent(new Event('DOMContentLoaded'));
  });
  await page.waitForTimeout(600);

  let state = await page.evaluate(() => ({
    rpc: window.__rpcCount,
    cartLen: cart.length,
    persisted: (JSON.parse(localStorage.getItem('coqorico_portail_cart_v1') || '[]')).length,
    badge: document.getElementById('cart-badge').textContent
  }));
  check('restauration de session : AUCUN place_order', state.rpc === 0, 'rpc=' + state.rpc);
  check('panier restauré INTACT (mémoire)', state.cartLen === 1);
  check('panier restauré INTACT (localStorage)', state.persisted === 1);
  check('badge panier affiché', state.badge === '1');

  // ── 2. CYCLE LOGOUT / RE-LOGIN (restauration forcée) ──
  await page.evaluate(async () => {
    await handleSignout();                      // vide le panier (confidentialité) — documenté
    cart = [{ produit_id: 'poulet_entier', nom: 'Poulet entier', unite: 'unite',
      prix_kg_fcfa: 2400, quantite_kg: 3 }];
    saveCart();
    document.getElementById('screen-login').classList.add('hidden');
    await enterApp();                           // « re-login »
  });
  await page.waitForTimeout(400);
  state = await page.evaluate(() => ({ rpc: window.__rpcCount, cartLen: cart.length }));
  check('logout + re-login : AUCUN place_order', state.rpc === 0, 'rpc=' + state.rpc);
  check('panier re-restauré dans le Panier, pas soumis', state.cartLen === 1);

  // ── 3. CLIC SYNTHÉTIQUE (script) sur #submit-order : IGNORÉ (isTrusted) ──
  await page.evaluate(() => {
    switchView('panier');
    document.getElementById('submit-order').dispatchEvent(new MouseEvent('click', { bubbles: true }));
  });
  await page.waitForTimeout(400);
  state = await page.evaluate(() => ({ rpc: window.__rpcCount }));
  check('clic SYNTHÉTIQUE ignoré (isTrusted=false)', state.rpc === 0, 'rpc=' + state.rpc);

  // ── 4. Appel programmatique direct de submitOrder hors panier : REFUSÉ ──
  await page.evaluate(async () => { switchView('catalogue'); await submitOrder(); });
  state = await page.evaluate(() => ({ rpc: window.__rpcCount }));
  check('submitOrder() programmatique hors Panier refusé', state.rpc === 0, 'rpc=' + state.rpc);

  // ── 5. CONTRÔLE POSITIF : un vrai clic utilisateur soumet (1 seul RPC) ──
  await page.evaluate(() => switchView('panier'));
  await page.click('#submit-order');            // clic Playwright = isTrusted
  await page.waitForTimeout(600);
  state = await page.evaluate(() => ({
    rpc: window.__rpcCount, cartLen: cart.length,
    confirm: !document.getElementById('view-confirm').classList.contains('hidden')
  }));
  check('clic utilisateur réel : EXACTEMENT 1 place_order', state.rpc === 1, 'rpc=' + state.rpc);
  check('panier vidé APRÈS soumission réussie seulement', state.cartLen === 0);
  check('écran de confirmation affiché', state.confirm === true);

  check('zéro erreur JS', pageErrors.length === 0, pageErrors.join(' | ') || 'aucune');

  await browser.close();
  console.log(failures === 0 ? '\nRÉGRESSION COMMANDE FANTÔME : TOUT PASSE' : '\nÉCHEC : ' + failures + ' assertion(s)');
  process.exit(failures === 0 ? 0 : 1);
})().catch(e => { console.error('TEST FAILED TO RUN:', e); process.exit(1); });
