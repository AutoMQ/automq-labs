"""Customer decisions, historical evidence and safe terminal behavior."""
import contextlib
import copy
import io
import json
import pathlib
import unittest

from cross_az.presenter import DisplayError, Presenter, text_width
from cross_az import demo
import test_demo as lifecycle


class Clock:
    def __init__(self): self.now = 100
    def __call__(self): return self.now


class Tty(io.StringIO):
    def isatty(self): return True


def sample(cross=12345):
    frame = {
        'client_id': 'client-a', 'actual_zone_id': 'example-az1', 'phase': 'before',
        'sample_seq': 10, 'sample_time': '2026-11-11T12:00:00+00:00', 'elapsed_seconds': 30,
        'window_seconds': 10, 'warmup_seconds': 10, 'capture_frame_age_ms': 250,
        'window': {r: {'tx_bytes': value, 'rx_bytes': value + 1 if value else 0} for r, value in (('same', 10000), ('cross', cross), ('unknown', 0))},
        'totals': {r: {'tx_bytes': value, 'rx_bytes': value} for r, value in (('same', 30000), ('cross', cross * 3), ('unknown', 0))},
        'quality': {'complete': True, 'source_verified': True, 'scope_intact': True, 'kernel_drops': 0, 'parse_errors': 0, 'queue_drops': 0},
        'peers': [{'ip': '10.40.2.10', 'port': 9092, 'zone_id': 'example-az2', 'relation': 'cross', 'tx_bytes': cross, 'rx_bytes': cross + 1 if cross else 0}],
        'workload': {'produce_active': True, 'consume_active': True, 'frames_fresh': True,
                     'window_success': {'produce': {'messages': 78, 'payload_bytes': 79872, 'covered_seconds': 10}, 'consume': {'messages': 90, 'payload_bytes': 92160, 'covered_seconds': 10}}},
        'role_states': {'watch': 'running', 'produce': 'running', 'consume': 'running'},
        'task_id': 'internal-watch-id', 'scope_id': 'internal-scope-id',
        'drained': True, 'successful_messages': 600, 'successful_payload_bytes': 614400,
        'partition_coverage': ['topic:0'], 'cohort': ['client-a'], 'topology_fingerprint': 'same', 'workload_fingerprint': 'same',
    }
    return {'frame': frame, 'age': 2.0, 'workload': frame['workload'],
            'producer': {'messages': 600, 'sent_messages': 777, 'payload_bytes': 614400, 'errors': 0, 'unconfirmed_messages': 0},
            'consumer': {'messages': 600, 'payload_bytes': 614400, 'errors': 0}, 'saved': True, 'client': 'client-a'}


class PresenterTests(unittest.TestCase):
    def test_broken_output_and_tty_failures_disable_only_display_after_first_error(self):
        calls = []
        def broken(value):
            calls.append(value)
            raise BrokenPipeError()
        presenter = Presenter(broken)
        with self.assertRaises(DisplayError): presenter.message('first')
        self.assertTrue(presenter.disabled)
        presenter.message('later')
        presenter.stage('Stopping', best_effort=True)
        self.assertEqual(['first'], calls)
        for operation in ('write', 'flush'):
            with self.subTest(operation=operation):
                stream = Tty()
                def failed(*args): raise OSError('sink closed')
                setattr(stream, operation, failed)
                presenter = Presenter(details=True, stream=stream, size=lambda: (200, 100))
                with self.assertRaises(DisplayError): presenter.live([sample()])
                self.assertTrue(presenter.disabled)
                presenter.stage('Cleaning', best_effort=True)

    def test_customer_text_distinguishes_round_and_window_and_preserves_real_peers(self):
        for lang in ('en', 'zh'):
            with self.subTest(lang=lang):
                output = []
                presenter = Presenter(output.append, lang=lang)
                lines, _ = presenter.frame_lines(sample())
                value = '\n'.join(lines)
                for exact in ('600', '78', '90', '12345 B', '12346 B', '10.40.2.10:9092', 'example-az2'):
                    self.assertIn(exact, value)
                for internal in ('777', 'internal-watch-id', 'internal-scope-id', 'Quality {', 'ACK+1', "'complete':"):
                    self.assertNotIn(internal, value)
                self.assertNotIn('\x1b', value)

    def test_one_byte_never_rounds_to_zero_and_unknown_never_claims_zero(self):
        output = []
        presenter = Presenter(output.append, details=True)
        item = sample(cross=1)
        presenter.live([item])
        self.assertIn('1 B', '\n'.join(output))
        self.assertIn('Cross-AZ bytes observed', '\n'.join(output))
        item['frame']['window']['cross'] = {'tx_bytes': 0, 'rx_bytes': 0}
        item['frame']['window']['unknown']['rx_bytes'] = 1
        self.assertEqual('incomplete', presenter.assessment(item['frame'], 2, item['workload'])[0])

    def test_zero_is_never_inferred_from_missing_stale_or_degraded_data(self):
        presenter = Presenter()
        cases = [('age', 'stale'), ('warming', 'warming'), ('waiting', 'waiting'),
                 ('unknown', 'incomplete'), ('drop', 'incomplete'), ('source', 'incomplete'),
                 ('missing-counter', 'incomplete'), ('missing-bytes', 'incomplete')]
        for condition, expected in cases:
            with self.subTest(condition=condition):
                item = sample(cross=0)
                if condition == 'age': item['age'] = 16
                if condition == 'warming': item['frame']['warmup_seconds'] = 40
                if condition == 'waiting': item['workload']['consume_active'] = False
                if condition == 'unknown': item['frame']['window']['unknown']['tx_bytes'] = 1
                if condition == 'drop': item['frame']['quality']['kernel_drops'] = 1
                if condition == 'source': item['frame']['quality']['source_verified'] = False
                if condition == 'missing-counter': item['frame']['quality'].pop('queue_drops')
                if condition == 'missing-bytes': item['frame']['window']['unknown'].pop('rx_bytes')
                state, reason = presenter.assessment(item['frame'], item['age'], item['workload'])
                self.assertEqual(expected, state)
                self.assertNotIn('No cross-AZ TCP traffic observed', reason)
        item = sample(cross=0)
        self.assertIn('No cross-AZ TCP traffic observed', presenter.assessment(item['frame'], 2, item['workload'])[1])

    def test_missing_business_counts_are_unknown_and_attempts_are_not_acks(self):
        presenter = Presenter()
        value = presenter.cumulative({'sent_messages': 600}, {})
        self.assertNotIn('600', value)
        self.assertNotIn('sent 0', value)
        self.assertIn('unknown', value)

    def test_non_tty_deduplicates_but_stale_quality_errors_and_roles_bypass_throttle(self):
        output, clock = [], Clock()
        presenter = Presenter(output.append, details=True, clock=clock)
        item = sample()
        presenter.live([item]); self.assertEqual(1, len(output))
        clock.now += 100
        presenter.live([item]); self.assertEqual(1, len(output), 'same frame must not be reprinted')
        item['age'] = 16
        presenter.live([item]); self.assertEqual(2, len(output), 'age degradation must be visible without a new sequence')
        item['age'] = 2
        presenter.live([item]); self.assertEqual(3, len(output))
        item['frame']['sample_seq'] += 1
        clock.now += 1
        presenter.live([item]); self.assertEqual(3, len(output), 'new normal frame is throttled')
        item['producer']['errors'] = 1
        presenter.live([item]); self.assertEqual(4, len(output))
        item['producer']['unconfirmed_messages'] = 1
        presenter.live([item]); self.assertEqual(5, len(output))
        item['frame']['role_states']['consume'] = 'failed'
        presenter.live([item]); self.assertEqual(6, len(output))
        item['frame']['quality']['kernel_drops'] = 2
        presenter.live([item]); self.assertEqual(7, len(output))
        presenter.stage('Cleaning')
        self.assertIn('Cleaning', output[-1])
        self.assertNotIn('\x1b', '\n'.join(output))

    def test_tty_only_erases_its_own_bounded_area_and_narrow_falls_back(self):
        for width, expects_cursor in ((200, True), (40, False)):
            with self.subTest(width=width):
                stream, clock = Tty(), Clock()
                presenter = Presenter(lambda text: stream.write(text + '\n'), lang='zh', details=True, stream=stream, clock=clock, size=lambda: (width, 100))
                item = sample()
                presenter.live([item])
                clock.now += 4
                item['frame']['sample_seq'] += 1
                presenter.live([item])
                value = stream.getvalue()
                self.assertEqual(expects_cursor, '\x1b[' in value)
                self.assertNotIn('\x1b[2J', value)
                self.assertNotIn('\x1b[H', value)
                if not expects_cursor:
                    self.assertTrue(all(text_width(line) <= width - 1 for line in value.splitlines()))
                self.assertIn('12345 B', value)

    def test_unsafe_tty_uses_append_interval_and_terminal_diagnostics_are_historical(self):
        stream, clock = Tty(), Clock()
        presenter = Presenter(lambda value: stream.write(value + '\n'), details=True, stream=stream, clock=clock, size=lambda: (40, 24))
        item = sample()
        presenter.live([item])
        first = stream.getvalue()
        item['frame']['sample_seq'] += 1
        clock.now += 4
        presenter.live([item])
        self.assertEqual(first, stream.getvalue())
        clock.now += 11
        presenter.live([item])
        self.assertGreater(len(stream.getvalue()), len(first))
        diagnostic = Presenter(details=True)
        lines, _ = diagnostic.frame_lines(sample(), historical=True)
        self.assertIn('HISTORICAL final window', '\n'.join(lines))
        self.assertNotIn('LIVE window', '\n'.join(lines))
        item['frame']['role_states']['watch'] = 'stopped'
        lines, _ = Presenter().frame_lines(item)
        self.assertIn('Historical final capture', '\n'.join(lines))
        self.assertNotIn('Current sample', '\n'.join(lines))

    def test_final_retains_historical_business_window_and_next_action(self):
        output = []
        presenter = Presenter(output.append, lang='zh', details=True)
        item = sample()
        presenter.final('before', {'status': 'Succeeded', 'jobs': {'one': {'stop_confirmed': True}}, 'cleanup_confirmed': True}, [item], 'example-az1@10.40.1.0/24', '/absolute/demo after', True, True)
        value = '\n'.join(output)
        self.assertIn('历史有效业务窗口', value)
        self.assertIn(item['frame']['sample_time'], value)
        self.assertIn('12345 B', value)
        self.assertIn('78 条', value)
        self.assertIn('/absolute/demo after', value)
        self.assertNotIn('LIVE', value)
        self.assertIn('未修改或回读', value)

    def test_failed_partial_round_and_unconfirmed_stop_are_not_success(self):
        output = []
        presenter = Presenter(output.append)
        item = {'saved': False, 'client': 'client-a', 'producer': {'messages': 164, 'payload_bytes': 167936}, 'consumer': {'messages': 163, 'payload_bytes': 166912}}
        presenter.final('before', {'status': 'Failed', 'failure': 'Stop requested', 'jobs': {'one': {'stop_confirmed': False}}, 'cleanup_confirmed': False}, [item])
        value = '\n'.join(output)
        self.assertIn('failed or cancelled', value)
        self.assertIn('164', value); self.assertIn('163', value)
        self.assertIn('stop unconfirmed', value)
        self.assertNotIn('Next:', value)
        self.assertNotIn('Round completed', value)

    def test_historical_success_with_current_unknown_stop_prioritizes_recovery(self):
        output = []
        Presenter(output.append, lang='zh').final('before', {'status': 'Succeeded', 'jobs': {'one': {'stop_confirmed': True}}, 'cleanup_confirmed': True}, [sample()], 'candidate-cidr', '/absolute/demo after', False, True)
        value = '\n'.join(output)
        self.assertIn('历史执行完成；本次停止核验未确认', value)
        self.assertIn('status/stop', value)
        self.assertNotIn('candidate-cidr', value)
        self.assertNotIn('/absolute/demo after', value)

    def test_details_are_explicit_and_comparison_does_not_manufacture_percentages(self):
        before, after = sample()['frame'], sample(cross=0)['frame']
        after['workload']['window_success']['consume']['messages'] = 79
        for lang in ('en', 'zh'):
            presenter = Presenter(lang=lang)
            value = presenter.comparison(before, after)
            self.assertIn('不可直接比较' if lang == 'zh' else 'Not directly comparable', value)
            self.assertNotIn('%', value)
        output = []
        Presenter(output.append, details=True).live([sample()])
        self.assertIn('internal-watch-id', '\n'.join(output))


class DemoPresentationIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.base = lifecycle.DemoTests()
        self.base.setUp()
        self.addCleanup(self.base.doCleanups)

    def test_readonly_status_keeps_old_state_and_selected_input_candidate_is_complete(self):
        base = self.base
        for number, client in ((2, 'client-b'), (3, 'client-c')):
            base.case['clients'][client].update(zone_id='example-az' + str(number), source_ip='10.40.' + str(number) + '.10', source_cidrs=['10.40.' + str(number) + '.0/24'])
        base.config.write_text(json.dumps(base.case))
        directory = base.begin(clients='client-a')
        base.api.expected_clients = 1
        run = base.round(directory)
        run.run()
        snapshot = {str(p): p.read_bytes() for p in base.store.root.rglob('*') if p.is_file()}
        output = io.StringIO()
        renewals = len(base.api.renewals)
        with contextlib.redirect_stdout(output):
            result = demo.main(['status', '--config', str(base.config), '--state-dir', str(base.store.root), '--lang', 'zh', '--details'], api=base.api)
        self.assertEqual(0, result)
        self.assertEqual(snapshot, {str(p): p.read_bytes() for p in base.store.root.rglob('*') if p.is_file()})
        self.assertEqual(renewals, len(base.api.renewals))
        text = output.getvalue()
        self.assertIn('历史有效业务窗口', text)
        self.assertIn('original-business-time', text)
        self.assertIn('controller_id', text)
        self.assertIn('技术阶段状态', text)
        self.assertIn('当前模板', text)
        brief = io.StringIO()
        with contextlib.redirect_stdout(brief):
            result = demo.main(['status', '--config', str(base.config), '--state-dir', str(base.store.root), '--lang', 'zh'], api=base.api)
        self.assertEqual(0, result)
        self.assertIn('automq.zone.cidr.blocks=example-az1@10.40.1.0/24<>example-az2@10.40.2.0/24<>example-az3@10.40.3.0/24', brief.getvalue())
        self.assertNotIn('status --details', brief.getvalue())
        self.assertLessEqual(len(brief.getvalue().splitlines()), 8)
        self.assertEqual(snapshot, {str(p): p.read_bytes() for p in base.store.root.rglob('*') if p.is_file()})
        self.assertEqual(renewals, len(base.api.renewals))

    def test_running_display_failure_still_stops_every_owned_task_and_cleans_scopes(self):
        base = self.base
        run = base.round(base.begin())
        run.presenter.details = True
        def failing_running(value):
            if value == 'Sending and consuming test data': raise BrokenPipeError()
        run.output = failing_running
        with self.assertRaisesRegex(demo.CaseError, 'Terminal output is unavailable'):
            run.run()
        phase = run.phase_state()
        self.assertEqual('Failed', phase['status'])
        self.assertTrue(phase['cleanup_confirmed'])
        self.assertTrue(all(j['stop_confirmed'] for j in phase['jobs'].values()))
        self.assertEqual(3, sum(j['descriptor']['role'] == 'scope-cleanup' for j in phase['jobs'].values()))
        mutable = {j['descriptor']['task_id'] for j in phase['jobs'].values() if j['descriptor']['role'] != 'scope-cleanup'}
        self.assertTrue(mutable.issubset(base.api.stopped))

    def test_running_tty_write_or_flush_failure_still_stops_and_cleans_all_owned_work(self):
        for failing_operation in ('write', 'flush'):
            with self.subTest(operation=failing_operation):
                base = lifecycle.DemoTests()
                base.setUp()
                try:
                    run = base.round(base.begin())
                    run.presenter.details = True
                    stream = Tty()
                    stream.armed = False
                    original = getattr(stream, failing_operation)
                    def failed(*args):
                        if stream.armed: raise OSError('terminal closed')
                        return original(*args)
                    setattr(stream, failing_operation, failed)
                    def output(value):
                        if value == 'Sending and consuming test data': stream.armed = True
                    run.output = output
                    run.presenter.stream, run.presenter.size = stream, lambda: (200, 100)
                    with self.assertRaisesRegex(demo.CaseError, 'Terminal output is unavailable'):
                        run.run()
                    phase = run.phase_state()
                    self.assertEqual('Failed', phase['status'])
                    self.assertTrue(phase['cleanup_confirmed'])
                    self.assertTrue(all(j['stop_confirmed'] for j in phase['jobs'].values()))
                    self.assertEqual(3, sum(j['descriptor']['role'] == 'scope-cleanup' for j in phase['jobs'].values()))
                    mutable = {j['descriptor']['task_id'] for j in phase['jobs'].values() if j['descriptor']['role'] != 'scope-cleanup'}
                    self.assertTrue(mutable.issubset(base.api.stopped))
                finally:
                    base.doCleanups()

    def test_teardown_stage_io_failures_never_skip_stop_or_cleanup(self):
        for stage, error in ((s, e) for s in ('Stopping', 'Cleaning') for e in (BrokenPipeError, KeyboardInterrupt)):
            with self.subTest(stage=stage, error=error):
                base = lifecycle.DemoTests()
                base.setUp()
                try:
                    run = base.round(base.begin())
                    run.presenter.details = True
                    for client in run.cohort:
                        run.controllers[client].check()
                        run.submit(client, 'scope-prepare')
                    run.submit(run.cohort[0], 'topic')
                    label = 'Stopping this round’s processes' if stage == 'Stopping' else 'Cleaning this round’s capture environment'
                    def broken(value):
                        if value == label: raise error()
                    run.output = broken
                    self.assertTrue(run.teardown())
                    self.assertTrue(run.presenter.disabled)
                    self.assertEqual(error is KeyboardInterrupt, run.presenter.interrupted)
                    phase = run.phase_state()
                    self.assertTrue(phase['cleanup_confirmed'])
                    self.assertTrue(all(j['stop_confirmed'] for j in phase['jobs'].values()))
                    self.assertEqual(3, sum(j['descriptor']['role'] == 'scope-cleanup' for j in phase['jobs'].values()))
                    self.assertEqual(4, len(base.api.stopped))
                finally:
                    base.doCleanups()

    def test_status_survives_missing_template_with_explicit_partial_candidate(self):
        base = self.base
        directory = base.begin(clients='client-a')
        base.api.expected_clients = 1
        base.round(directory).run()
        base.config.unlink()
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            result = demo.main(['status', '--config', str(base.config), '--state-dir', str(base.store.root), '--lang', 'zh', '--details'], api=base.api)
        self.assertEqual(0, result)
        self.assertIn('仅覆盖本轮客户端', output.getvalue())
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            result = demo.main(['status', '--config', str(base.config), '--state-dir', str(base.store.root), '--lang', 'zh'], api=base.api)
        self.assertEqual(0, result)
        self.assertIn('仅覆盖本轮客户端', output.getvalue())
        self.assertIn('保留其他来源', output.getvalue())
        self.assertIn('勿直接覆盖', output.getvalue())
        self.assertIn('automq.zone.cidr.blocks=example-az1@10.40.1.0/24', output.getvalue())
        self.assertNotIn('example-az2@', output.getvalue())

    def test_display_warmup_uses_actual_case_setting(self):
        base = self.base
        directory = base.begin(clients='client-a')
        base.api.expected_clients = 1
        run = base.round(directory)
        run.presenter.details = True
        run.case['observation']['warmup_seconds'] = 40
        item = sample()
        output = []
        run.output = output.append
        sampled = {'client-a/watch': {'last_frame': item['frame'], 'task_id': 'watch', 'frame_age_ms': 100, '_case_received_mono': base.clock()},
                   'client-a/produce': {'last_frame': item['producer'], 'frame_age_ms': 100, '_case_received_mono': base.clock()},
                   'client-a/consume': {'last_frame': item['consumer'], 'frame_age_ms': 100, '_case_received_mono': base.clock()}}
        run.show(sampled)
        self.assertIn('Waiting for a full independent observation window', '\n'.join(output))
        self.assertNotIn('No cross-AZ TCP traffic observed', '\n'.join(output))


if __name__ == '__main__':
    unittest.main()


class SummaryOnlyTests(unittest.TestCase):
    def test_default_run_messages_are_one_start_and_no_sampling_or_stage_output(self):
        output = []
        presenter = Presenter(output.append, lang='zh')
        presenter.start('before', {'workload': {}}, ['client-a'])
        for _ in range(5):
            presenter.stage('Running producers')
            presenter.live([sample()], force=True)
        self.assertEqual(1, len(output))
        self.assertIn('完成后显示摘要', output[0])
        self.assertNotIn('10.40.', output[0])

    def test_default_success_is_short_and_details_keep_original_evidence(self):
        for lang in ('en', 'zh'):
            output = []
            presenter = Presenter(output.append, lang=lang)
            presenter.final('before', {'status': 'Succeeded', 'jobs': {'one': {'stop_confirmed': True}}, 'cleanup_confirmed': True}, [sample()], 'candidate-cidr', '/absolute/demo after', True, True)
            value = '\n'.join(output)
            self.assertLessEqual(len(value.splitlines()), 8)
            self.assertIn('600', value)
            self.assertIn('12.3 KB', value)
            self.assertIn('historical' if lang == 'en' else '历史', value)
            self.assertIn('automq.zone.cidr.blocks=candidate-cidr', value)
            self.assertIn('Candidate configuration' if lang == 'en' else '候选配置', value)
            self.assertNotIn('status --details', value)
            for hidden in ('78', '90', '12345 B', '10.40.2.10', '/absolute/demo after', 'Network totals', 'Quality {'):
                self.assertNotIn(hidden, value)
            details = []
            Presenter(details.append, lang=lang, details=True).final('before', {'status': 'Succeeded', 'jobs': {}, 'cleanup_confirmed': True}, [sample()], 'candidate-cidr', '/absolute/demo after', True, True)
            diagnostic = '\n'.join(details)
            for exact in ('12345 B', '10.40.2.10', 'candidate-cidr', '/absolute/demo after', sample()['frame']['sample_time']):
                self.assertIn(exact, diagnostic)

    def test_summary_missing_and_partial_candidates_are_not_complete_mapping_advice(self):
        phase = {'status': 'Succeeded', 'jobs': {'one': {'stop_confirmed': True}}, 'cleanup_confirmed': True}
        for lang in ('en', 'zh'):
            output = []
            Presenter(output.append, lang=lang).final('before', phase, [sample()], candidate='one-client-cidr', candidate_complete=False)
            value = '\n'.join(output)
            self.assertIn('only this round' if lang == 'en' else '仅覆盖本轮客户端', value)
            self.assertIn('preserve other sources' if lang == 'en' else '保留其他来源', value)
            self.assertIn('automq.zone.cidr.blocks=one-client-cidr', value)
            self.assertLessEqual(len(value.splitlines()), 8)
            output = []
            Presenter(output.append, lang=lang).final('before', phase, [sample()])
            value = '\n'.join(output)
            self.assertIn('candidate unavailable' if lang == 'en' else '候选配置不可用', value)
            self.assertNotIn('automq.zone.cidr.blocks=', value)
            self.assertNotIn('run after' if lang == 'en' else '运行 after', value)

    def test_summary_failure_and_after_do_not_repeat_application_candidate(self):
        for status in ('Failed', 'Recovery required'):
            for lang in ('en', 'zh'):
                output = []
                phase = {'status': status, 'jobs': {}, 'cleanup_confirmed': False}
                Presenter(output.append, lang=lang).final('before', phase, [sample()], 'candidate-cidr', candidate_complete=True)
                value = '\n'.join(output)
                self.assertNotIn('candidate-cidr', value)
                self.assertNotIn('run after' if lang == 'en' else '运行 after', value)
        output = []
        Presenter(output.append).final('after', {'status': 'Succeeded', 'jobs': {}, 'cleanup_confirmed': True}, [sample()], 'candidate-cidr', candidate_complete=True)
        self.assertNotIn('automq.zone.cidr.blocks=', '\n'.join(output))

    def test_after_summary_compares_both_windows_and_keeps_uncertainty(self):
        for unequal in (False, True):
            output = []
            item = sample(cross=0)
            item['baseline'] = sample()['frame']
            if unequal:
                item['frame']['workload']['window_success']['consume']['messages'] = 79
            Presenter(output.append, lang='zh').final('after', {'status': 'Succeeded', 'jobs': {}, 'cleanup_confirmed': True}, [item], verified_stopped=True)
            value = '\n'.join(output)
            self.assertLessEqual(len(value.splitlines()), 8)
            self.assertIn('配置前（历史 10 秒）', value)
            self.assertIn('配置后（历史 10 秒）', value)
            self.assertIn('12.3 KB', value)
            self.assertIn('0 B', value)
            self.assertIn('不可直接比较' if unequal else '可直接比较', value)
            self.assertNotIn('%', value)
            self.assertNotIn('已生效', value)

    def test_tiny_residual_and_missing_unknown_are_not_zero_conclusions(self):
        for mode in ('tiny', 'missing', 'unknown', 'drop', 'stale'):
            output = []
            item = sample(cross=1 if mode == 'tiny' else 0)
            if mode == 'missing': item['frame']['window']['unknown'].pop('rx_bytes')
            if mode == 'unknown': item['frame']['window']['unknown']['rx_bytes'] = 1
            if mode == 'drop': item['frame']['quality']['kernel_drops'] = 1
            if mode == 'stale': item['age'] = 16
            Presenter(output.append, lang='zh').final('after', {'status': 'Succeeded', 'jobs': {}, 'cleanup_confirmed': True}, [item], verified_stopped=True)
            value = '\n'.join(output)
            self.assertNotIn('未观测到跨 AZ TCP', value)
            if mode == 'tiny': self.assertIn('发送 1 B', value)
            if mode == 'missing': self.assertIn('未知对端 未知', value)

    def test_default_fake_round_is_quiet_and_still_drains_and_cleans(self):
        base = lifecycle.DemoTests()
        base.setUp()
        try:
            base.api.expected_clients = 1
            run = base.round(base.begin(clients='client-a'))
            output = []
            run.output = output.append
            run.run()
            value = '\n'.join(output)
            self.assertLessEqual(len(value.splitlines()), 8)
            self.assertEqual(1, sum('summary appears' in line for line in value.splitlines()))
            self.assertNotIn('Physical peer', value)
            self.assertNotIn('original-business-time', value)
            phase = run.phase_state()
            self.assertEqual('Succeeded', phase['status'])
            self.assertTrue(phase['cleanup_confirmed'])
            self.assertTrue(all(j['stop_confirmed'] for j in phase['jobs'].values()))
        finally:
            base.doCleanups()
