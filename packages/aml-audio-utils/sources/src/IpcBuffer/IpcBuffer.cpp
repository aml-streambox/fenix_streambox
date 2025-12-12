#include <algorithm> // for std::min
#include <iostream>
#include <cstring>

#include <boost/interprocess/sync/scoped_lock.hpp>
#include <boost/interprocess/managed_shared_memory.hpp>

#include "audio_server_shmem.h"
#include "IpcBuffer.h"
#include "IpcBuffer_c.h"

using namespace boost::interprocess;

IpcBuffer::IpcBuffer(const char *name, size_t capacity)
  : begin_index_(0)
  , end_index_(0)
  , size_(0)
  , capacity_(capacity)
  , name_(std::string(name))
  , wr_position_(0)
  , blocking_(false)
  , wr_time_(0)
  , underrun_(0)
  , silence_inserted_(0)
{
  managed_shared_memory *segment = audio_server_shmem::getInstance();
  void *shptr = segment->allocate(capacity);
  handle_ = segment->get_handle_from_address(shptr);
}

IpcBuffer::~IpcBuffer()
{
  managed_shared_memory *segment = audio_server_shmem::getInstance();
  uint8_t *base = static_cast<uint8_t *>(segment->get_address_from_handle(handle_));
  segment->deallocate(base);
}

size_t IpcBuffer::write(const uint8_t *data, size_t bytes)
{
  if (bytes == 0) return 0;

  uint8_t *ptr = static_cast<uint8_t *>(audio_server_shmem::getInstance()->get_address_from_handle(handle_));
  size_t capacity = capacity_;
  size_t bytes_to_write = std::min(bytes, capacity - size_);

  if (bytes_to_write <= capacity - end_index_) {
    memcpy(ptr + end_index_, data, bytes_to_write);
    end_index_ += bytes_to_write;
    if (end_index_ == capacity) end_index_ = 0;
  } else {
    size_t size_1 = capacity - end_index_;
    memcpy(ptr + end_index_, data, size_1);
    size_t size_2 = bytes_to_write - size_1;
    memcpy(ptr, data + size_1, size_2);
    end_index_ = size_2;
  }

  size_ += bytes_to_write;
  return bytes_to_write;
}

size_t IpcBuffer::read(uint8_t *data, size_t bytes)
{
  if (bytes == 0) return 0;

  uint8_t *ptr = static_cast<uint8_t *>(audio_server_shmem::getInstance()->get_address_from_handle(handle_));
  size_t capacity = capacity_;
  size_t bytes_to_read = std::min(bytes, size_);

  if (bytes_to_read <= capacity - begin_index_) {
    memcpy(data, ptr + begin_index_, bytes_to_read);
    begin_index_ += bytes_to_read;
    if (begin_index_ == capacity) begin_index_ = 0;
  } else {
    size_t size_1 = capacity - begin_index_;
    memcpy(data, ptr + begin_index_, size_1);
    size_t size_2 = bytes_to_read - size_1;
    memcpy(data + size_1, ptr, size_2);
    begin_index_ = size_2;
  }

  size_ -= bytes_to_read;
  return bytes_to_read;
}

void IpcBuffer::write_nb(const uint8_t *data, size_t bytes)
{
  if (bytes == 0) return;

  const uint8_t *ptr = data;
  size_t len = bytes;
  uint8_t *base = static_cast<uint8_t *>(audio_server_shmem::getInstance()->get_address_from_handle(handle_));

  while (len > 0) {
    size_t bytes_to_write = std::min(capacity_ - end_index_, len);
    memcpy(base + end_index_, ptr, bytes_to_write);
    ptr += bytes_to_write;
    len -= bytes_to_write;
    end_index_ += bytes_to_write;
    if (end_index_ == capacity_) end_index_ = 0;
  }

  scoped_lock<interprocess_mutex> lock(mutex_);

  timespec ts;
  clock_gettime(CLOCK_MONOTONIC_RAW, &ts);
  wr_position_ += bytes;
  wr_time_ = uint64_t(ts.tv_sec) * 1000000000 + uint64_t(ts.tv_nsec);
}

void IpcBuffer::get_write_position(uint64_t& time, uint64_t& position)
{
  scoped_lock<interprocess_mutex> lock(mutex_);
  time = wr_time_;
  position = wr_position_;
}

uint8_t* IpcBuffer::start_ptr()
{
  return static_cast<uint8_t *>(audio_server_shmem::getInstance()->get_address_from_handle(handle_));
}

const char *IpcBuffer::name()
{
  return name_.c_str();
}

void IpcBuffer::reset()
{
  scoped_lock<interprocess_mutex> lock(mutex_);
  begin_index_ = end_index_ = size_ = wr_position_ = 0;
}

void IpcBuffer::setMeta(uint64_t meta_64, uint32_t meta_32)
{
  scoped_lock<interprocess_mutex> lock(mutex_);
  clock_gettime(CLOCK_MONOTONIC_RAW, &meta_ts_);
  meta_64_ = meta_64;
  meta_32_ = meta_32;
}

void IpcBuffer::getMeta(struct timespec *meta_ts, uint64_t *meta_64, uint32_t *meta_32)
{
  scoped_lock<interprocess_mutex> lock(mutex_);
  meta_ts->tv_sec = meta_ts_.tv_sec;
  meta_ts->tv_nsec = meta_ts_.tv_nsec;
  *meta_64 = meta_64_;
  *meta_32 = meta_32_;
}

managed_shared_memory *audio_server_shmem::shm_;

extern "C" {

void *IpcBuffer_create(const char *name, size_t size)
{
  managed_shared_memory *shm = audio_server_shmem::getInstance();
  IpcBuffer * cb = shm->find<IpcBuffer>(name).first;
  if (cb) {
    IpcBuffer_destroy(cb);
  }
  cb = shm->construct<IpcBuffer>(name)(name, size);
  return cb;
}

void IpcBuffer_destroy(void *cb)
{
  managed_shared_memory *shm = audio_server_shmem::getInstance();
  shm->destroy<IpcBuffer>(((IpcBuffer *)(cb))->name());
}

void IpcBuffer_write(void *cb, const unsigned char *buf, int size)
{
  ((IpcBuffer *)(cb))->write_nb(buf, size);
}

uint8_t *IpcBuffer_get_ptr(const char *name)
{
  managed_shared_memory *shm = audio_server_shmem::getInstance();
  IpcBuffer * cb = shm->find<IpcBuffer>(name).first;
  if (cb) {
    return cb->start_ptr();
  }
  return NULL;
}

uint64_t IpcBuffer_get_wr_pos(const char *name)
{
  managed_shared_memory *shm = audio_server_shmem::getInstance();
  IpcBuffer * cb = shm->find<IpcBuffer>(name).first;
  if (cb) {
    uint64_t time, position;
    cb->get_write_position(time, position);
    return position;
  }
  return 0;
}

size_t IpcBuffer_get_capacity(const char *name)
{
  managed_shared_memory *shm = audio_server_shmem::getInstance();
  IpcBuffer * cb = shm->find<IpcBuffer>(name).first;
  if (cb) {
    return cb->capacity();
  }
  return 0;
}

void *IpcBuffer_get_by_name(const char *name)
{
  managed_shared_memory *shm = audio_server_shmem::getInstance();
  return shm->find<IpcBuffer>(name).first;
}

void IpcBuffer_set_meta_byname(const char *name, uint64_t meta_64, uint32_t meta_32)
{
  managed_shared_memory *shm = audio_server_shmem::getInstance();
  IpcBuffer * cb = shm->find<IpcBuffer>(name).first;
  if (cb) {
    cb->setMeta(meta_64, meta_32);
  }
}

void IpcBuffer_inc_underrun_byname(const char *name)
{
  managed_shared_memory *shm = audio_server_shmem::getInstance();
  IpcBuffer * cb = shm->find<IpcBuffer>(name).first;
  if (cb) {
    cb->incUnderrun();
  }
}

void IpcBuffer_add_silence_byname(const char *name, size_t size)
{
  managed_shared_memory *shm = audio_server_shmem::getInstance();
  IpcBuffer * cb = shm->find<IpcBuffer>(name).first;
  if (cb) {
    cb->addSilence(size);
  }
}

void IpcBuffer_setMeta_byname(const char *name, uint64_t meta_64, uint32_t meta_32)
{
  managed_shared_memory *shm = audio_server_shmem::getInstance();
  IpcBuffer * cb = shm->find<IpcBuffer>(name).first;
  if (cb) {
    cb->setMeta(meta_64, meta_32);
  }
}

void IpcBuffer_inc_underrun(void *instance)
{
  IpcBuffer * cb = (IpcBuffer *)instance;
  if (cb) {
    cb->incUnderrun();
  }
}

void IpcBuffer_add_silence(void *instance, size_t size)
{
  IpcBuffer * cb = (IpcBuffer *)instance;
  if (cb) {
    cb->addSilence(size);
  }
}

void IpcBuffer_setMeta(void *instance, uint64_t meta_64, uint32_t meta_32)
{
  IpcBuffer * cb = (IpcBuffer *)instance;
  if (cb) {
    cb->setMeta(meta_64, meta_32);
  }
}


}
