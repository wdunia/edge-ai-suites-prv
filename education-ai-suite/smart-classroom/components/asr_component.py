from components.base_component import PipelineComponent
import os
import time
import torch
import torch.serialization
from utils.config_loader import config
from utils.storage_manager import StorageManager
from utils.runtime_config_loader import RuntimeConfig
from components.asr.openai.whisper import Whisper as OA_Whisper
from components.asr.openvino.whisper import Whisper as OV_Whisper
from components.asr.funasr.paraformer import Paraformer
import logging
import whisperx
logger = logging.getLogger(__name__)

torch.serialization.add_safe_globals([torch.torch_version.TorchVersion])

DELETE_CHUNK_AFTER_USE = config.pipeline.delete_chunks_after_use
threads_limit = config.models.asr.threads_limit
THREADS_LIMIT = threads_limit if threads_limit and threads_limit > 0 else None


class ASRComponent(PipelineComponent):
    _model = None
    _config = None

    def _log_debug(self, message: str, debug_type: str = "info"):
        """Centralized debug logging with icons."""
        if not self.debug_enabled:
            return

        icons = {
            "info": "🔍",
            "success": "✅",
            "error": "❌",
            "warning": "⚠️",
            "process": "⚙️"
        }
        icon = icons.get(debug_type, "🔍")
        print(f"{icon} DEBUG: {message}")

    def __init__(self, session_id, provider="openai", model_name="whisper-small",
                 device="CPU", temperature=0.0, diarization=True, hf_token=None, debug=True):
        self.debug_enabled = debug
        self.session_id = session_id
        self.temperature = temperature
        self.provider = provider
        self.model_name = model_name
        self.threads_limit = THREADS_LIMIT
        self.diarization = diarization
        self.hf_token = hf_token
        self.device = device.lower() if device.upper() == "CPU" else device

        self._log_debug(f"ASRComponent.__init__ called with diarization={diarization}")
        self._log_debug(f"Device set to: {self.device}")

        self._setup_diarization()
        self._setup_asr_model(provider, model_name, device)

    def _setup_diarization(self):
        """Load diarization models with fallback strategies."""
        if not self.diarization:
            self.align_model = self.align_metadata = self.diarize_model = None
            return

        self._log_debug("Loading diarization models...", "process")
        try:
            self._log_debug("Loading alignment model...")
            self.align_model, self.align_metadata = whisperx.load_align_model(
                language_code="en", device=self.device
            )
            self._log_debug("Alignment model loaded successfully", "success")

            self.diarize_model = self._load_diarization_pipeline()

            if self.device != "cpu":
                self.diarize_model.to(torch.device(self.device))

            logger.info("Diarization models loaded successfully")
            self._log_debug("All diarization setup complete", "success")

        except Exception as e:
            self._log_debug(f"Diarization setup failed: {e}", "error")
            logger.warning(f"Failed to load diarization models: {e}")
            self.diarization = False
            self.align_model = self.align_metadata = self.diarize_model = None

    def _load_diarization_pipeline(self):
        """Try loading diarization with safe globals, fallback to monkey patch."""
        from pyannote.audio import Pipeline

        try:
            from pyannote.audio.core.task import Specifications, Problem
            with torch.serialization.safe_globals([
                torch.torch_version.TorchVersion, Specifications, Problem
            ]):
                pipeline = Pipeline.from_pretrained(
                    "pyannote/speaker-diarization-3.1",
                    use_auth_token=self.hf_token
                )
                self._log_debug("Diarization loaded with safe globals", "success")
                return pipeline

        except Exception as e:
            self._log_debug(f"Safe globals failed: {e}", "warning")
            self._log_debug("Trying with monkey patch...", "process")

            import functools
            old_load = torch.load
            torch.load = functools.wraps(old_load)(
                lambda *args, **kwargs: old_load(*args, weights_only=False, **{k: v for k, v in kwargs.items() if k != 'weights_only'})
            )
            try:
                pipeline = Pipeline.from_pretrained(
                    "pyannote/speaker-diarization-3.1",
                    use_auth_token=self.hf_token
                )
                self._log_debug("Diarization loaded with monkey patch", "success")
                return pipeline
            finally:
                torch.load = old_load

    def _setup_asr_model(self, provider, model_name, device):
        """Initialize ASR model based on provider."""
        provider, model_name = provider.lower(), model_name.lower()
        config = (provider, model_name, device)

        if ASRComponent._model is None or ASRComponent._config != config:
            if provider == "openai" and "whisper" in model_name:
                ASRComponent._model = OA_Whisper(model_name, device, None)
            elif provider == "openvino" and "whisper" in model_name:
                ASRComponent._model = OV_Whisper(model_name, device, None, self.threads_limit)
            elif provider == "funasr" and "paraformer" in model_name:
                ASRComponent._model = Paraformer(model_name, device.lower(), None)
            else:
                raise ValueError(f"Unsupported ASR provider/model: {provider}/{model_name}")
            ASRComponent._config = config

        self.asr = ASRComponent._model

    def process(self, input_generator):
        project_config = RuntimeConfig.get_section("Project")
        project_path = os.path.join(project_config.get("location"), project_config.get("name"), self.session_id)
        start_time = time.perf_counter()
        default_torch_threads = None

        try:
            if self.provider in ["openai", "funasr"] and self.threads_limit and self.threads_limit > 0:
                default_torch_threads = torch.get_num_threads()
                torch.set_num_threads(self.threads_limit)

            for chunk_data in input_generator:
                chunk_path = chunk_data["chunk_path"]
                self._log_debug(f"Processing chunk: {chunk_path}")

                asr_result = self.asr.transcribe(chunk_path, temperature=self.temperature)

                if isinstance(asr_result, dict):
                    transcribed_text = asr_result.get("text", "")
                else:
                    transcribed_text = str(asr_result)

                self._log_debug(f"Extracted text: '{transcribed_text}'")

                transcribed_text = self._format_with_diarization(transcribed_text, chunk_path)

                StorageManager.save(os.path.join(project_path, "transcription.txt"), transcribed_text + "\n", append=True)

                yield {
                    **chunk_data,  # keep all chunk metadata
                    "text": transcribed_text
                }
        finally:
            if default_torch_threads is not None:
                torch.set_num_threads(default_torch_threads)
            end_time = time.perf_counter()
            transcription_time = end_time - start_time

            StorageManager.update_csv(
                path=os.path.join(project_path, "performance_metrics.csv"),
                new_data={
                    "configuration.asr_model": f"{self.provider}/{self.model_name}",
                    "performance.transcription_time": round(transcription_time, 4)
                }
            )

            logger.info(f"Transcription Complete: {self.session_id}")

    def _format_with_diarization(self, text, chunk_path):
        """Format text with speaker diarization and timestamps."""
        if not self.diarization or not self.diarize_model:
            return f"[00:00-00:00] ⚪ Speaker_1: {text}"

        try:
            self._log_debug("Starting real diarization...", "process")

            diarization = self.diarize_model(chunk_path)
            segments = [
                {'start': turn.start, 'end': turn.end, 'speaker': speaker}
                for turn, _, speaker in diarization.itertracks(yield_label=True)
            ]

            self._log_debug(f"Found {len(segments)} speaker segments: {segments}")

            if not segments:
                return f"[00:00-00:00] ⚪ Speaker_1: {text}"

            merged = self._merge_speaker_segments(segments)
            self._log_debug(f"Merged to {len(merged)} segments: {merged}")

            formatted_text = self._format_transcript_lines(text.split(), merged)
            self._log_debug(f"Text formatted with timestamps: {formatted_text}", "success")

            return formatted_text

        except Exception as e:
            self._log_debug(f"Diarization failed: {e}", "error")
            return f"[00:00-00:00] ⚪ Speaker_1: {text}"

    def _merge_speaker_segments(self, segments, gap_threshold=1.0):
        """Merge consecutive segments from same speaker."""
        merged = []
        current = None

        for seg in segments:
            if current and current['speaker'] == seg['speaker'] and seg['start'] - current['end'] < gap_threshold:
                current['end'] = seg['end']
            else:
                if current:
                    merged.append(current)
                current = seg.copy()

        if current:
            merged.append(current)

        return merged

    def _format_transcript_lines(self, words, segments):
        """Format words with speaker labels and timestamps."""
        COLORS = {'SPEAKER_00': '🔵', 'SPEAKER_01': '🔴', 'SPEAKER_02': '🟢', 'SPEAKER_03': '🟡'}

        lines = []
        word_idx = 0
        total_duration = max(seg['end'] for seg in segments)

        for seg in segments:
            ratio = (seg['end'] - seg['start']) / total_duration
            word_count = max(5, int(len(words) * ratio))
            seg_words = words[word_idx:word_idx + word_count]
            word_idx += word_count

            if seg_words:
                start = f"{int(seg['start'] // 60):02d}:{int(seg['start'] % 60):02d}"
                end = f"{int(seg['end'] // 60):02d}:{int(seg['end'] % 60):02d}"
                icon = COLORS.get(seg['speaker'], '⚪')
                lines.append(f"[{start}-{end}] {icon} {seg['speaker']}: {' '.join(seg_words)}")

        if word_idx < len(words):
            remaining = words[word_idx:]
            last = segments[-1]
            start = f"{int(last['start'] // 60):02d}:{int(last['start'] % 60):02d}"
            end = f"{int(last['end'] // 60):02d}:{int(last['end'] % 60):02d}"
            icon = COLORS.get(last['speaker'], '⚪')
            lines.append(f"[{start}-{end}] {icon} {last['speaker']}: {' '.join(remaining)}")

        return "\n".join(lines)
