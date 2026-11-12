"""Local customer-facing text. Raw evidence and decisions remain unchanged."""
import copy
import math
import shutil
import time
import unicodedata

from .view import compare, observation, render


STAGES = {
    'check': ('Checking cloud clients', '检查云上客户端'),
    'Preparing topic': ('Preparing the test topic', '准备测试 topic'),
    'Preparing owned scopes and source proof': ('Verifying the traffic capture source', '准备采集并核验流量来源'),
    'Waiting for all capture frames': ('Waiting for traffic capture', '等待采集就绪'),
    'Waiting for every consumer current-end barrier': ('Waiting for consumers to be ready', '等待消费就绪'),
    'Checking cohort ready barrier': ('Confirming all consumers are ready', '确认所有消费者已就绪'),
    'Running producers': ('Sending and consuming test data', '发送并消费测试数据'),
    'Draining every consumer to cohort final ACK+1': ('Waiting for all test messages to be consumed', '等待本轮消息全部消费完成'),
    'Stopping': ('Stopping this round’s processes', '停止本轮进程'),
    'Cleaning': ('Cleaning this round’s capture environment', '清理本轮采集环境'),
}


def text_width(value):
    return sum(0 if unicodedata.combining(c) else 2 if unicodedata.east_asian_width(c) in ('W', 'F') else 1 for c in value)


def wrap(value, width):
    """Wrap, never truncate. Exact bytes and recovery commands remain intact."""
    lines = []
    for logical in str(value).split('\n'):
        current, used = '', 0
        for char in logical:
            count = text_width(char)
            if current and used + count > width:
                boundary = current.rfind(' ')
                if boundary > 0:
                    lines.append(current[:boundary])
                    current = current[boundary + 1:]
                    used = text_width(current)
                else:
                    lines.append(current)
                    current, used = '', 0
            current += char
            used += count
        lines.append(current)
    return lines


class DisplayError(Exception):
    """An output sink failed; lifecycle code must still stop owned work."""


class Presenter:
    def __init__(self, emit=print, lang='en', details=False, stream=None, clock=time.monotonic, size=None):
        self.emit, self.lang, self.details = emit, lang, details
        self.stream, self.clock = stream, clock
        self.size = size or (lambda: shutil.get_terminal_size((100, 24)))
        self.last_key = self.last_state = None
        self.last_update = float('-inf')
        self.drawn = 0
        self.drawn_width = None
        self.disabled = False
        self.interrupted = False

    def io(self, operation):
        if self.disabled:
            return None
        try:
            return operation()
        except (OSError, ValueError) as error:
            # Closed pipes/streams and terminal I/O failures disable only the
            # display. The first failure still aborts a running round normally.
            self.disabled, self.drawn = True, 0
            raise DisplayError('Terminal output is unavailable') from error

    def t(self, en, zh):
        return zh if self.lang == 'zh' else en

    def _clear(self):
        # Only erase the exact area previously drawn by this presenter. Never
        # clear a screen or move above unrelated stage/error output.
        if self.drawn:
            self.io(lambda: self.stream.write('\x1b[{}A'.format(self.drawn)))
            for _ in range(self.drawn):
                self.io(lambda: self.stream.write('\x1b[2K\n'))
            self.io(lambda: self.stream.write('\x1b[{}A'.format(self.drawn)))
            self.drawn = 0

    def message(self, value):
        if self.disabled:
            return
        # Keep an existing dashboard as history before appending a stage.
        self.drawn = 0
        self.drawn_width = None
        self.io(lambda: self.emit(value))
        if self.stream is not None:
            self.io(self.stream.flush)
        self.last_key = self.last_state = None

    def stage(self, value, best_effort=False):
        if not self.details:
            return
        labels = STAGES.get(value)
        try:
            self.message(self.t(*labels) if labels else value)
        except DisplayError:
            if not best_effort:
                raise
        except KeyboardInterrupt:
            if not best_effort:
                raise
            # An interruption of a teardown notification must not preempt
            # stopping owned work. Core stop/cleanup interrupt handling stays
            # with the lifecycle code; only this optional display is disabled.
            self.interrupted, self.disabled, self.drawn = True, True, 0

    def start(self, phase, case, cohort):
        if not self.details:
            self.message(self.t('{} test running; the summary appears when it finishes.', '{}测试进行中，完成后显示摘要。').format(
                self.t('Before-configuration', '配置前') if phase == 'before' else self.t('After-configuration', '配置后')))
            return
        self.message(self.t('Cross-AZ traffic check: {}', '跨 AZ 流量验证：{}').format(
            self.t('before configuration', '配置前') if phase == 'before' else self.t('after configuration', '配置后')))
        work = case['workload']
        budget = self.t('Per producer: {} B/s; {} B per message', '每个生产者：{} B/s；每条 {} B').format(
            format(work['rate_mibps'] * 1048576, '.6g'), work['record_bytes'])
        if 'max_messages' in work:
            budget += self.t('; at most {} messages', '；最多 {} 条').format(work['max_messages'])
        if 'duration_seconds' in work:
            budget += self.t('; at most {} seconds', '；最长 {} 秒').format(work['duration_seconds'])
        self.message(budget)
        self.message(self.t('Clients: {}. Kafka traffic and capture run on these cloud clients.',
                            '客户端：{}。收发与采集运行在这些云上客户端。').format(', '.join(cohort)))
        self.message(self.t('Network bytes include IP/TCP headers and retransmissions; they are not payload or cloud billing bytes.',
                            '网络字节包含 IP/TCP 包头和重传，与消息大小、云账单流量的统计口径不同。'))

    def count(self, value):
        return str(value) if isinstance(value, int) and not isinstance(value, bool) and value >= 0 else self.t('unknown', '尚无数据')

    def bytes(self, value):
        if not isinstance(value, int) or isinstance(value, bool) or value < 0:
            return self.t('unknown', '尚无数据')
        if value >= 1000000:
            return '{:.2f} MB ({} B)'.format(value / 1000000, value)
        if value >= 1000:
            return '{:.1f} KB ({} B)'.format(value / 1000, value)
        return '{} B'.format(value)

    def relation(self, relation):
        return {'same': self.t('Same AZ', '同 AZ'), 'cross': self.t('Cross AZ', '跨 AZ'),
                'unknown': self.t('Unknown peers', '未知对端')}.get(relation, self.t('Unknown peers', '未知对端'))

    def assessment(self, frame, age, workload):
        window = frame.get('window', {})
        def counter(value):
            return isinstance(value, int) and not isinstance(value, bool) and value >= 0
        if any(not counter(window.get(r, {}).get(d)) for r in ('same', 'cross', 'unknown') for d in ('tx_bytes', 'rx_bytes')):
            return 'incomplete', self.t('Network sample is incomplete; cannot determine cross-AZ traffic.', '网络采样不完整，暂时无法判断跨 AZ 流量。')
        if any(not counter(frame.get('quality', {}).get(k)) for k in ('kernel_drops', 'parse_errors', 'queue_drops')):
            return 'incomplete', self.t('Capture loss counters are unknown; cannot determine cross-AZ traffic.', '采集丢包或解析计数未知，暂时无法判断跨 AZ 流量。')
        state, reason = observation(frame, age, workload, frame.get('warmup_seconds', 10))
        translations = {
            'Remote frame stale; zero-byte conclusion unavailable': '采样已陈旧，暂时无法判断跨 AZ 流量。检查客户端状态。',
            'Capture/source/scope incomplete; zero-byte conclusion unavailable': '采集或来源核验不完整，暂时无法判断跨 AZ 流量。',
            'Waiting for a full independent observation window': '正在预热，等待完整采样窗口。',
            'Waiting for successful producer and consumer progress': '等待成功发送和消费，尚不能判断跨 AZ 流量。',
            'Unknown TCP peers observed; zero-byte conclusion unavailable': '存在未知位置的连接，无法确认没有跨 AZ 流量。核对对端拓扑。',
            'Cross-AZ bytes observed in this window': '此窗口已观测到跨 AZ 流量。',
            'No captured successful workload path; zero-byte conclusion unavailable': '尚未采集到有效业务路径，暂时无法判断跨 AZ 流量。',
            'No cross-AZ TCP traffic observed in this window (client scope, L3 bytes)': '此客户端在本窗口内未观测到跨 AZ TCP 流量。',
        }
        return state, translations.get(reason, reason) if self.lang == 'zh' else reason

    def quality(self, frame):
        quality = frame.get('quality', {})
        issues = []
        for key, en, zh in (('complete', 'capture incomplete', '采集不完整'),
                            ('source_verified', 'source not verified', '来源未核验'),
                            ('scope_intact', 'capture boundary changed', '采集范围未确认')):
            if not quality.get(key):
                issues.append(self.t(en, zh))
        for key, en, zh in (('kernel_drops', 'dropped packets', '丢包'), ('parse_errors', 'parse errors', '解析失败'), ('queue_drops', 'queue drops', '采集队列丢弃')):
            value = quality.get(key)
            if value:
                issues.append('{} {}'.format(self.t(en, zh), value))
            elif value is None:
                issues.append(self.t(en + ' unknown', zh + '数量未知'))
        return self.t('Capture: complete; source verified; no capture loss or parse errors.', '采集：完整；来源已核验；无采集丢包或解析错误。') if not issues else self.t('Capture: ', '采集：') + '; '.join(issues)

    def cumulative(self, producer, consumer):
        parts = []
        for role, frame, en, zh in (('produce', producer, 'confirmed sent', '已确认发送'), ('consume', consumer, 'consumed', '成功消费')):
            parts.append('{} {} {} / {}'.format(self.t(en, zh), self.count(frame.get('messages')), self.t('messages', '条'), self.bytes(frame.get('payload_bytes'))))
            for key, en_label, zh_label in (('errors', 'errors', '错误'), ('unconfirmed_messages', 'unconfirmed writes', '未确认写入')):
                if key == 'unconfirmed_messages' and role != 'produce':
                    continue
                value = frame.get(key)
                if value is None or value:
                    parts.append('{} {}'.format(self.t(en_label, zh_label), self.count(value)))
        return self.t('Round totals: ', '本轮累计：') + ' | '.join(parts)

    def window_lines(self, frame, age, workload, historical=False, heading=None, history_title=None):
        state, conclusion = self.assessment(frame, age, workload)
        label = (history_title or self.t('Historical business window', '历史有效业务窗口')) if historical else self.t('Stale last sample', '陈旧末次采样') if state == 'stale' else self.t('Current sample', '当前采样')
        if heading:
            label = heading + ' | ' + label
        sample = frame.get('sample_time') or self.t('unknown', '未知')
        age_text = '{:.1f}s'.format(age) if isinstance(age, (int, float)) and math.isfinite(age) else self.t('unknown', '未知')
        sample_line = self.t('Sample {} | {}s window', '采样 {} | 窗口 {} 秒').format(sample, frame.get('window_seconds', '?'))
        sample_line += self.t(' | historical, not current traffic', ' | 历史数据，非当前流量') if historical else self.t(' | sample age {}', ' | 样本年龄 {}').format(age_text)
        lines = [label + ': ' + conclusion, sample_line]
        success = workload.get('window_success', {})
        lines.append(self.t('Within this window: sent {} / consumed {} messages.', '此窗口内成功：发送 {} 条 / 消费 {} 条。').format(
            self.count(success.get('produce', {}).get('messages')), self.count(success.get('consume', {}).get('messages'))))
        lines.append(self.t('Network direction is from the cloud client: send to broker / receive from broker.', '方向以云上客户端为准：发送到 broker / 从 broker 接收。'))
        for relation in ('same', 'cross', 'unknown'):
            counts = frame.get('window', {}).get(relation, {})
            lines.append('{}: {} {} | {} {}'.format(self.relation(relation), self.t('send', '发送'), self.bytes(counts.get('tx_bytes')), self.t('receive', '接收'), self.bytes(counts.get('rx_bytes'))))
        totals = frame.get('totals', {})
        totals_label = self.t('Network totals through this sample (send / receive): ', '截至该采样的网络累计（发送 / 接收）：') if historical else self.t('Network totals (send / receive): ', '网络累计（发送 / 接收）：')
        lines.append(totals_label + ' | '.join(
            '{} {} / {}'.format(self.relation(r), self.bytes(totals.get(r, {}).get('tx_bytes')), self.bytes(totals.get(r, {}).get('rx_bytes'))) for r in ('same', 'cross', 'unknown')))
        lines.append(self.quality(frame))
        for peer in frame.get('peers', []):
            lines.append('{}:{} | {} | {} | {} {} / {} {}'.format(peer.get('ip', '?'), peer.get('port', '?'), peer.get('zone_id') or self.t('unknown AZ', '未知 AZ'), self.relation(peer.get('relation')), self.t('send', '发送'), self.bytes(peer.get('tx_bytes')), self.t('receive', '接收'), self.bytes(peer.get('rx_bytes'))))
        return lines, state

    def frame_lines(self, item, historical=False, heading=None):
        frame = item['frame']
        lines = [self.t('Client {} | actual AZ {}', '客户端 {} | 实际 AZ {}').format(frame.get('client_id', '?'), frame.get('actual_zone_id') or self.t('unverified', '未核验')),
                 self.cumulative(item.get('producer', {}), item.get('consumer', {}))]
        workload = item['workload']
        stopped = not historical and frame.get('role_states', {}).get('watch') in ('stopped', 'failed')
        if stopped:
            workload = dict(workload, frames_fresh=False)
        window, state = self.window_lines(frame, item['age'], workload, historical or stopped, heading,
                                          self.t('Historical final capture; capture has stopped', '历史末次采样；采集已停止') if stopped else None)
        lines.extend(window)
        if self.details:
            lines.append(self.t('Technical details', '技术详情'))
            diagnostic = copy.deepcopy(frame)
            if historical:
                diagnostic.setdefault('role_states', {})['watch'] = 'stopped'
            lines.append(render(diagnostic, item['age'], workload, frame.get('warmup_seconds', 10), item.get('baseline')))
        return lines, state

    def live(self, items, force=False):
        if not self.details or self.disabled or not items:
            return
        lines, states, keys = [], [], []
        for item in items:
            block, state = self.frame_lines(item)
            lines.extend(block)
            states.append((item['frame'].get('client_id'), state, self.quality(item['frame']),
                           tuple(item['frame'].get('window', {}).get('unknown', {}).values()),
                           bool(sum(item['frame'].get('window', {}).get('cross', {}).values())),
                           tuple((item.get(role) or {}).get(key) for role in ('producer', 'consumer') for key in ('errors', 'unconfirmed_messages')),
                           tuple(sorted(item['frame'].get('role_states', {}).items()))))
            keys.append((item['frame'].get('client_id'), item['frame'].get('sample_seq'), item['frame'].get('sample_time')))
        key, status = tuple(keys), tuple(states)
        changed = status != self.last_state
        now = self.clock()
        width, height = self.io(self.size)
        width = max(12, width - 1)
        physical = [line for logical in lines for line in wrap(logical, width)]
        tty = self.stream is not None and self.io(self.stream.isatty)
        safe = tty and width >= 80 and len(physical) < height - 2
        if not force and not changed and (key == self.last_key or now - self.last_update < (3 if safe else 15)):
            return
        if self.drawn and (not safe or width != self.drawn_width):
            # Terminal reflow makes the old coordinates unknowable.
            self.drawn = 0
        if safe:
            self._clear()
            self.io(lambda: self.stream.write('\n'.join(physical) + '\n'))
            self.io(self.stream.flush)
            self.drawn, self.drawn_width = len(physical), width
        else:
            self.io(lambda: self.emit('\n'.join(physical)))
            if self.stream is not None:
                self.io(self.stream.flush)
        self.last_key, self.last_state, self.last_update = key, status, now

    def comparison(self, baseline, current):
        result = compare(baseline, current)
        if result['comparable']:
            return self.t('The retained business windows are comparable.', '两轮保留业务窗口可直接比较。')
        reasons = []
        for reason in result['reasons']:
            value = reason
            if self.lang == 'zh':
                replacements = {
                    'Baseline has no cross-AZ distinction': '配置前未观测到跨 AZ，基线缺少区分度',
                    'topology_fingerprint differs': '两轮客户端或 broker 拓扑不同',
                    'workload_fingerprint differs': '两轮负载参数不同',
                    'window_seconds differs': '两轮窗口时长不同',
                    'cohort differs': '两轮客户端集合不同',
                    'Actual successful_messages differs': '两轮实际成功发送量不同',
                    'Actual successful_payload_bytes differs': '两轮实际成功消息字节不同',
                    'Actual partition_coverage differs': '两轮实际分区覆盖不同',
                }
                value = replacements.get(reason, reason)
                for phase, translated in (('before', '配置前'), ('after', '配置后')):
                    value = value.replace(phase + ' capture/source incomplete', translated + '采集或来源不完整')
                    value = value.replace(phase + ' has unknown peers', translated + '存在未知对端')
                    value = value.replace(phase + ' offset boundary incomplete', translated + '未确认全部消费完成')
                    value = value.replace(phase + ' has no successful business traffic', translated + '缺少成功业务流量')
                    value = value.replace(phase + ' window was not fresh, warm and carrying successful business traffic', translated + '窗口的新鲜度、预热或成功业务量不足')
                    for role, direction in (('produce', '发送'), ('consume', '消费')):
                        value = value.replace(phase + ' ' + role + ' window success/coverage incomplete', translated + direction + '窗口成功量或时间覆盖不足')
                for role, direction in (('produce', '发送'), ('consume', '消费')):
                    for key, label in (('messages', '条数'), ('payload_bytes', '消息字节')):
                        value = value.replace('Actual window ' + role + ' ' + key + ' differs', '两轮窗口实际' + direction + label + '不同')
            elif reason.startswith('Actual window '):
                value = reason.replace('Actual window produce messages', 'Successful messages sent within each window').replace('Actual window consume messages', 'Successful messages consumed within each window').replace('Actual window produce payload_bytes', 'Payload bytes sent within each window').replace('Actual window consume payload_bytes', 'Payload bytes consumed within each window')
            reasons.append(value)
        return self.t('Not directly comparable: ', '不可直接比较：') + '; '.join(reasons)

    def compact_bytes(self, value):
        if not isinstance(value, int) or isinstance(value, bool) or value < 0:
            return self.t('unknown', '未知')
        if value >= 1000000:
            return '{:.1f} MB'.format(value / 1000000)
        if value >= 1000:
            return '{:.1f} KB'.format(value / 1000)
        return '{} B'.format(value)

    def summary_network(self, frame, label):
        window = frame.get('window', {})
        cross, unknown = window.get('cross', {}), window.get('unknown', {})
        unknown_values = [unknown.get(key) for key in ('tx_bytes', 'rx_bytes')]
        unknown_total = sum(unknown_values) if all(isinstance(v, int) and not isinstance(v, bool) and v >= 0 for v in unknown_values) else None
        return self.t('{} (historical {}s): cross-AZ send {} / receive {}; unknown peers {}.',
                      '{}（历史 {} 秒）：跨 AZ 发送 {} / 接收 {}；未知对端 {}。').format(
            label, frame.get('window_seconds', '?'), self.compact_bytes(cross.get('tx_bytes')),
            self.compact_bytes(cross.get('rx_bytes')), self.compact_bytes(unknown_total))

    def brief_comparison(self, baseline, current):
        result = compare(baseline, current)
        if result['comparable']:
            return self.t('Comparison: retained windows are comparable.', '对照：保留窗口可直接比较。')
        reasons = result['reasons']
        if 'Baseline has no cross-AZ distinction' in reasons:
            reason = self.t('the baseline has no cross-AZ distinction', '配置前缺少跨 AZ 区分度')
        elif any('Actual window ' in r or 'window success/coverage' in r for r in reasons):
            reason = self.t('actual window workload or coverage differs', '窗口内实际收发量或覆盖不同')
        elif any('Actual ' in r for r in reasons):
            reason = self.t('actual business totals or partition coverage differs', '实际业务量或分区覆盖不同')
        elif any('capture/source' in r or 'unknown peers' in r or 'fresh, warm' in r for r in reasons):
            reason = self.t('capture validity or successful workload is incomplete', '采集有效性或成功业务量不足')
        elif any('offset boundary' in r for r in reasons):
            reason = self.t('consumption completion is unconfirmed', '消费完成边界未确认')
        else:
            reason = self.t('topology or test conditions differ', '拓扑或测试条件不同')
        return self.t('Not directly comparable: {}; full reasons in --details.', '不可直接比较：{}；完整原因见 --details。').format(reason)

    def final_summary(self, phase, phase_state, items, verified_stopped=None, candidate=None, candidate_complete=False):
        status = phase_state['status']
        phase_name = self.t('Before-configuration', '配置前') if phase == 'before' else self.t('After-configuration', '配置后')
        labels = {'Succeeded': self.t('completed', '完成'), 'Failed': self.t('failed or cancelled', '失败或已取消'),
                  'Recovery required': self.t('recovery required', '需要恢复')}
        title = labels.get(status, self.t('still running', '仍在执行'))
        if status == 'Succeeded' and verified_stopped is False:
            title = self.t('historically completed; current stop is unconfirmed', '历史执行完成；本次停止核验未确认')
        self.message('{}{}{}'.format(phase_name, self.t(' test: ', '测试：'), title))
        if phase_state.get('failure'):
            self.message(self.t('Reason: ', '原因：') + phase_state['failure'])
        for item in items:
            producer, consumer = item.get('producer', {}), item.get('consumer', {})
            label = item.get('client') or item.get('frame', {}).get('client_id', '?')
            business = self.t('{}: confirmed sent {} / consumed {} messages.', '{}：已确认发送 {} 条 / 成功消费 {} 条。').format(
                label, self.count(producer.get('messages')), self.count(consumer.get('messages')))
            errors = []
            for frame, keys in ((producer, ('errors', 'unconfirmed_messages')), (consumer, ('errors',))):
                for key in keys:
                    if frame.get(key):
                        errors.append('{} {}'.format(self.t('unconfirmed writes', '未确认写入') if key == 'unconfirmed_messages' else self.t('errors', '错误'), self.count(frame[key])))
            self.message(business + (' ' + '; '.join(errors) if errors else ''))
            if not item.get('saved'):
                self.message(self.t('Result: no successful business window is saved; cross-AZ traffic cannot be assessed.',
                                    '结果：未保存成功业务窗口，暂时无法判断跨 AZ 流量。'))
                continue
            frame = item['frame']
            if item.get('baseline'):
                self.message(self.summary_network(item['baseline'], self.t('Before', '配置前')))
            self.message(self.summary_network(frame, self.t('Before', '配置前') if phase == 'before' else self.t('After', '配置后')))
            if status == 'Succeeded':
                state, reason = self.assessment(frame, item['age'], item['workload'])
                if phase == 'before' and state == 'observing' and not sum(frame.get('window', {}).get('cross', {}).values()):
                    reason = self.t('the baseline has no cross-AZ distinction; it cannot establish an improvement.', '配置前缺少跨 AZ 区分度，尚不能证明配置带来改善。')
                self.message(self.t('Result: ', '结论：') + reason)
            if item.get('baseline'):
                self.message(self.brief_comparison(item['baseline'], frame))
        confirmed = all(j.get('stop_confirmed') for j in phase_state['jobs'].values()) and verified_stopped is not False
        self.message(self.t('Processes: {} | Capture cleanup: {}.', '进程：{}；采集清理：{}。').format(
            self.t('stopped', '已停止') if confirmed else self.t('stop unconfirmed', '停止未确认'),
            self.t('confirmed', '已确认') if phase_state.get('cleanup_confirmed') else self.t('unconfirmed', '未确认')))
        if verified_stopped is False:
            self.message(self.t('Next: use status/stop to confirm recovery before running after.', '下一步：先用 status/stop 确认恢复，再运行 after。'))
        elif status != 'Succeeded':
            self.message(self.t('This round is not a successful baseline or complete verification.', '本轮不能作为成功基线或完整验证结果。'))
        elif phase == 'before':
            if candidate:
                if not candidate_complete:
                    self.message(self.t('This candidate covers only this round’s clients. Verify the complete mapping and preserve other sources; do not replace existing configuration with this partial value.',
                                        '候选配置仅覆盖本轮客户端；须核对完整映射并保留其他来源，勿直接覆盖。'))
                self.message(self.t('Candidate configuration: ', '候选配置：') + 'automq.zone.cidr.blocks=' + candidate)
                self.message(self.t('Next: manually save and verify the complete mapping in the console, then run after.',
                                    '下一步：在控制台手动保存并核对完整映射后运行 after。'))
            else:
                self.message(self.t('CIDR candidate unavailable. Verify the original inputs; use status --details for diagnostics.',
                                    'CIDR 候选配置不可用。核对原输入；用 status --details 查看诊断。'))

    def final(self, phase, phase_state, items, candidate=None, after_command=None, verified_stopped=None, candidate_complete=False):
        self.drawn = 0
        if not self.details:
            return self.final_summary(phase, phase_state, items, verified_stopped, candidate, candidate_complete)
        status = phase_state['status']
        labels = {'Succeeded': self.t('Round completed', '本轮执行完成'), 'Failed': self.t('Round failed or cancelled', '本轮失败或已取消'), 'Recovery required': self.t('Recovery required', '需要恢复')}
        title = labels.get(status, self.t('Round is still active: ', '本轮仍在执行：') + status)
        if status == 'Succeeded' and verified_stopped is False:
            title = self.t('Historical round completed; current stop verification is incomplete', '历史执行已完成；本次停止核验尚未确认')
        self.message(title)
        confirmed = all(j.get('stop_confirmed') for j in phase_state['jobs'].values())
        if verified_stopped is not None:
            confirmed = confirmed and verified_stopped
        self.message(self.t('Processes: {} | Capture cleanup: {}', '本轮进程：{} | 采集环境清理：{}').format(
            self.t('stopped', '已停止') if confirmed else self.t('not confirmed stopped', '停止尚未确认'),
            self.t('confirmed', '已确认') if phase_state.get('cleanup_confirmed') else self.t('not confirmed', '尚未确认')))
        if phase_state.get('failure'):
            self.message(self.t('Reason: ', '原因：') + phase_state['failure'])
        if status == 'Succeeded' and phase == 'before':
            if any(sum(i['frame'].get('window', {}).get('cross', {}).values()) for i in items if i.get('saved')):
                self.message(self.t('Result: cross-AZ traffic was observed in the saved client business window.', '结果：已在保留的客户端业务窗口内观测到跨 AZ 流量。'))
            elif all(i.get('saved') for i in items):
                self.message(self.t('Result: the baseline has no cross-AZ distinction; it cannot establish an improvement.', '结果：基线缺少跨 AZ 区分度，尚不能证明配置带来改善。'))
            else:
                self.message(self.t('The saved business-window result is unavailable; cross-AZ traffic cannot be assessed.', '保留的业务窗口结果不可用，暂时无法判断跨 AZ 流量。'))
        self.message(self.t('Network bytes include IP/TCP headers and retransmissions; they are not payload or cloud billing bytes.',
                            '网络字节包含 IP/TCP 包头和重传，与消息大小、云账单流量的统计口径不同。'))
        for item in items:
            if not item.get('saved'):
                self.message(self.t('Client {}: no successful business-window result is saved.', '客户端 {}：未保存成功的业务窗口结果。').format(item['client']))
                self.message(self.cumulative(item.get('producer', {}), item.get('consumer', {})))
                continue
            lines, _ = self.frame_lines(item, historical=True)
            self.message('\n'.join(lines))
            if item.get('baseline'):
                baseline = item['baseline']
                earlier, _ = self.window_lines(baseline, baseline.get('capture_frame_age_ms', float('inf')) / 1000, baseline.get('workload', {}), True, self.t('Before configuration', '配置前'))
                self.message('\n'.join(earlier))
                self.message(self.comparison(baseline, item['frame']))
        if verified_stopped is False:
            self.message(self.t('Next: use status/stop to confirm this round’s processes are stopped. Do not start after while recovery is unconfirmed.',
                                '下一步：使用 status/stop 确认本轮进程已停止。恢复尚未确认时，不要启动 after。'))
        elif status != 'Succeeded':
            self.message(self.t('This round does not establish a successful baseline or a complete verification result.', '本轮不能作为成功基线或完整验证结果。'))
        elif phase == 'before':
            if candidate and after_command:
                self.message(self.t('CIDR candidate from the current matching template.', 'CIDR 候选值来自与本轮输入匹配的当前模板。') if candidate_complete else self.t(
                    'CIDR candidate covers only this round’s frozen clients. The original template is unavailable or changed. Verify the complete mapping before replacing any existing configuration.',
                    'CIDR 候选值仅覆盖本轮客户端。原模板不可用或已变化；填写前核对原完整映射，保留其他来源配置。'))
                self.message(self.t('Next: manually save and verify this candidate automq.zone.cidr.blocks value, then run after. No cluster configuration was changed or read back by this command.', '下一步：在控制台手动保存并核对以下 automq.zone.cidr.blocks 候选值，再运行 after。本命令未修改或回读集群配置。'))
                self.message(candidate)
                self.message(after_command)
        else:
            self.message(self.t('Execution completed. Use the actual retained bytes and comparison conditions to assess the routing change.', '本轮执行完成。根据实际保留字节与可比条件判断配置后的网络路径。'))
        if self.details:
            import json
            self.message(self.t('Technical phase state', '技术阶段状态'))
            self.message(json.dumps(phase_state, indent=2))
