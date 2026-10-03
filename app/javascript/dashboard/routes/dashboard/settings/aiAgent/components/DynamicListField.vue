<script setup>
import Input from 'dashboard/components-next/input/Input.vue';
import ButtonV4 from 'next/button/Button.vue';

const props = defineProps({
  modelValue: { type: Array, default: () => [] },
  placeholder: { type: String, default: '' },
  addLabel: { type: String, default: 'Add' },
});

const emit = defineEmits(['update:modelValue']);

const updateItem = (index, value) => {
  const next = [...props.modelValue];
  next[index] = value;
  emit('update:modelValue', next);
};

const addItem = () => emit('update:modelValue', [...props.modelValue, '']);

const removeItem = index => {
  const next = [...props.modelValue];
  next.splice(index, 1);
  emit('update:modelValue', next);
};
</script>

<template>
  <div class="flex flex-col gap-2">
    <div
      v-for="(item, index) in modelValue"
      :key="index"
      class="flex items-center gap-2"
    >
      <Input
        :model-value="item"
        :placeholder="placeholder"
        class="flex-1"
        @update:model-value="value => updateItem(index, value)"
      />
      <ButtonV4
        sm
        faded
        slate
        icon="i-lucide-x"
        @click="removeItem(index)"
      />
    </div>
    <ButtonV4
      sm
      faded
      blue
      icon="i-lucide-plus"
      :label="addLabel"
      class="self-start"
      @click="addItem"
    />
  </div>
</template>
