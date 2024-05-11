// SPDX-License-Identifier: MIT
// Copyright (c) 2024 Liu Rujia, International Digital Economy Academy

const AUDIO_BUFFERING = 512;
const SAMPLE_COUNT = 4 * 1024;
const SAMPLE_MASK = SAMPLE_COUNT - 1;
const audio_samples_L = new Float32Array(SAMPLE_COUNT);
const audio_samples_R = new Float32Array(SAMPLE_COUNT);
let audio_write_cursor = 0, audio_read_cursor = 0;


function nes_write_audio_sample(sample) {
    // only mono is supported now
    const l = sample;
    const r = sample;
    audio_samples_L[audio_write_cursor] = l;
    audio_samples_R[audio_write_cursor] = r;
    audio_write_cursor = (audio_write_cursor + 1) & SAMPLE_MASK;
}

function audio_remain() {
    return (audio_write_cursor - audio_read_cursor) & SAMPLE_MASK;
}

class AudioProcessor extends AudioWorkletProcessor {
    constructor() {
        super();
        this.port.onmessage = (e) => {
            nes_write_audio_sample(e.data)
        }
    }

    process(inputs, /** @type {Float32Array[][]} */ outputs, parameters) {
        // Attempt to avoid buffer underruns.
        if (audio_remain() < AUDIO_BUFFERING) {
            // TODO
            //nes.frame();
        }

        var dst_l = outputs[0][0];
        var dst_r = outputs[0][1];
        const len = dst_l.length;
        for (var i = 0; i < len; i++) {
            var src_idx = (audio_read_cursor + i) & SAMPLE_MASK;
            dst_l[i] = audio_samples_L[src_idx];
            dst_r[i] = audio_samples_R[src_idx];
        }

        audio_read_cursor = (audio_read_cursor + len) & SAMPLE_MASK;
        return true;
    }
}

registerProcessor('audio-processor', AudioProcessor);