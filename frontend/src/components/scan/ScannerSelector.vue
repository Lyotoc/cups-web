<template>
  <UCard>
    <template #header>
      <div class="flex items-center justify-between">
        <div class="flex items-center gap-2 font-semibold">
          <UIcon name="i-lucide-scan" class="w-5 h-5" />
          扫描仪
        </div>
        <UButton
          variant="ghost"
          size="xs"
          icon="i-lucide-refresh-cw"
          :loading="loading"
          @click="fetchScanners"
        />
      </div>
    </template>

    <!-- 加载中 -->
    <div v-if="loading" class="flex items-center gap-2 text-sm text-muted py-2">
      <UIcon name="i-lucide-loader-circle" class="w-4 h-4 animate-spin" />
      正在搜索扫描仪...
    </div>

    <!-- 请求失败 -->
    <div v-else-if="error" class="space-y-2 py-2">
      <div class="flex items-center gap-2 text-sm text-error">
        <UIcon name="i-lucide-alert-circle" class="w-4 h-4 shrink-0" />
        {{ error }}
      </div>
      <UButton size="xs" variant="outline" @click="fetchScanners">
        重试
      </UButton>
    </div>

    <!-- 扫描仪列表 -->
    <template v-else>
      <UFormField label="选择扫描仪">
        <USelect
          :model-value="modelValue"
          :items="scannerItems"
          value-key="value"
          label-key="label"
          class="w-full"
          :placeholder="scanners.length === 0 ? '未发现扫描仪' : '请选择扫描仪'"
          @update:model-value="onSelect"
        />
      </UFormField>
      <div v-if="scanners.length === 0" class="mt-2 flex items-center gap-2 text-sm text-muted">
        <UIcon name="i-lucide-info" class="w-4 h-4 shrink-0" />
        <span>未发现可用的扫描仪。请检查扫描仪是否已开机并连接到网络。</span>
      </div>
    </template>
  </UCard>
</template>

<script setup>
import { ref, onMounted } from 'vue'

const props = defineProps({
  modelValue: { type: String, default: '' }
})

const emit = defineEmits(['update:modelValue', 'change'])

const scanners = ref([])
const loading = ref(false)
const error = ref('')

const scannerItems = ref([])

function onSelect(val) {
  emit('update:modelValue', val)
  emit('change')
}

async function fetchScanners() {
  loading.value = true
  error.value = ''
  try {
    const response = await fetch('/api/scanners')
    if (response.ok) {
      const data = await response.json()
      scanners.value = Array.isArray(data) ? data : []
      scannerItems.value = scanners.value.map(s => ({
        label: `${s.name} — ${s.description || s.vendor + ' ' + s.model}`,
        value: s.device
      }))
    } else {
      error.value = `获取扫描仪列表失败 (${response.status})`
      scanners.value = []
      scannerItems.value = []
    }
  } catch (e) {
    error.value = '网络错误，无法连接到服务器'
    scanners.value = []
    scannerItems.value = []
  } finally {
    loading.value = false
  }
}

// 暴露 refresh 方法供父组件调用
defineExpose({ refresh: fetchScanners })

onMounted(() => {
  fetchScanners()
})
</script>
