# Docker Strategy for Schedulo Staging

## Current Approach: "Fat but Simple"

### Philosophy
We're optimizing for **iteration speed** and **deployment velocity** at the cost of image size. This is a pragmatic staging approach.

### How It Works
1. **Copy everything** - Local code, dependencies, builds
2. **Reuse local builds** - node_modules and .next from your Mac
3. **Skip npm registry** - No SSL issues, no slow downloads
4. **Fast deploys** - 5-10 mins instead of 30-40 mins

### Tradeoffs

#### ✅ What We Gain
- **Speed**: Deploy in ~5 mins vs 30+ mins
- **Reliability**: No SSL/npm registry issues
- **Simplicity**: Single-stage Dockerfile, easy to debug
- **Iteration**: Ship features fast, unblocked

#### ⚠️ What We Trade
- **Image size**: ~1.5GB (Railway handles this fine)
- **Reproducibility**: "Works on my machine" approach
- **Best practices**: Not production-grade (yet)

### When to Revisit

Rebuild a "proper" multi-stage Dockerfile when:
1. ✅ **Revenue**: Paying customers justify the infrastructure investment
2. ✅ **Scale**: Running multiple regions/instances
3. ✅ **Team**: DevOps resources available
4. ✅ **Bottleneck**: Build times block multiple developers

**Not before.** Right now, customer features > infrastructure perfection.

### Usage

#### Local Development
```bash
# Develop normally
yarn dx

# Build before Docker (optional but faster)
yarn workspace @calcom/web build
```

#### Deploy to Railway
```bash
# Commit and push - Railway auto-deploys
git add -A
git commit -m "feat: your feature"
git push origin staging
```

#### Test Locally (Optional)
```bash
# Build image (~5 mins)
docker build -t schedulo:staging .

# Run container
docker run -p 3000:3000 \
  -e DATABASE_URL="your-db-url" \
  -e NEXTAUTH_SECRET="your-secret" \
  -e CALENDSO_ENCRYPTION_KEY="your-key" \
  schedulo:staging
```

## Future: Production-Grade Dockerfile

When revenue/scale demands it, we'll implement:
- ✅ Multi-stage build (builder + runner)
- ✅ Clean `yarn install` from package.json
- ✅ Minimal final image (~300MB)
- ✅ Build-time caching strategies
- ✅ Security scanning

But today: **ship features, get customers, make revenue.**

---

*"Premature optimization is the root of all evil" - Donald Knuth*

