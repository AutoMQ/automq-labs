"""Read the environment's billing prerequisites from the trusted Home endpoint."""
import base64
import json
import urllib.error
import urllib.request
from core import SetupError

HOME_ORIGIN = 'https://console.automq.cloud'

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # Never forward environment credentials to another endpoint.
        return None


def subscription_status(body):
    if not body:
        raise SetupError('Home returned no UsageBased subscription for this environment. Ask the Home administrator to check UsageBasedSubscription and associate an available subscription or trial. Home ACTIVE alone is not sufficient. No AWS resources need to be prepared yet.')
    if not isinstance(body, dict):
        raise SetupError('Home returned an invalid subscription response.')
    payment = body.get('activePayment') or {}
    if body.get('state') == 'Trial' or (isinstance(payment, dict) and payment.get('state') == 'Valid'):
        return {'available': True, 'subscriptionState': body.get('state'), 'activePaymentState': payment.get('state') if isinstance(payment, dict) else None}
    raise SetupError('The environment has a UsageBased subscription but no available trial or valid payment. Resolve this in Home before preparing AWS resources.')


def read_subscription(home):
    auth = base64.b64encode((home['clientId'] + ':' + home['clientSecret']).encode()).decode()
    request = urllib.request.Request(HOME_ORIGIN + '/agentapi/v1/environments/postpaid-subscriptions', headers={'Authorization': 'Basic ' + auth})
    try:
        opener = urllib.request.build_opener(NoRedirect())
        with opener.open(request, timeout=30) as response:
            raw = response.read(1024 * 1024).decode()
        body = json.loads(raw) if raw.strip() else None
    except urllib.error.HTTPError as error:
        raise SetupError(f'Home subscription query failed (HTTP {error.code}). Check environment credentials and Home availability; no cloud resources were prepared.') from None
    except (urllib.error.URLError, TimeoutError, ValueError):
        raise SetupError('Home subscription query could not complete. Check network access to the trusted Home endpoint and retry; no cloud resources were prepared.') from None
    return subscription_status(body)


def prepare_public_dns(home, enable_tls):
    auth = base64.b64encode((home['clientId'] + ':' + home['clientSecret']).encode()).decode()
    request = urllib.request.Request(HOME_ORIGIN + '/agentapi/v1/environments/public-dns-zones',
        data=json.dumps({'enableTls': enable_tls}).encode(), method='POST',
        headers={'Authorization': 'Basic ' + auth, 'Content-Type': 'application/json'})
    try:
        with urllib.request.build_opener(NoRedirect()).open(request, timeout=30) as response:
            body = json.loads(response.read(1024 * 1024))
    except (urllib.error.URLError, TimeoutError, ValueError):
        raise SetupError('Home public DNS preparation failed. Check credentials and Home availability; do not substitute wildcard permissions.') from None
    import re
    if not isinstance(body, dict) or not re.fullmatch(r'(?:/hostedzone/)?Z[A-Z0-9]+', body.get('hostedZoneId', '')) or not re.fullmatch(r'arn:aws:iam::\d{12}:role/.+', body.get('crossAccountRole', '')):
        raise SetupError('Home response is missing a valid Zone ID or DNS Role ARN.')
    if enable_tls and (not isinstance(body.get('tlsCertificate'),dict) or not all(body['tlsCertificate'].get(k) for k in ['certificateChain','privateKey'])): raise SetupError('Home did not return the required TLS certificate.')
    return body
